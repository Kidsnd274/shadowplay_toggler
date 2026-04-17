import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../models/nvapi_state.dart';
import '../providers/database_provider.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/nvapi_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/scan_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';
import '../widgets/add_program_dialog.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/backup_dialog.dart';
import '../widgets/exe_drop_target.dart';
import '../widgets/left_pane.dart';
import '../widgets/reconciliation_banner.dart';
import '../widgets/right_pane.dart';
import '../widgets/scan_controller.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _reconciliationStarted = false;
  bool _autoScanTriggered = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(nvapiProvider.notifier).initialize();
      await _restoreLastScanAt();
    });
  }

  Future<void> _restoreLastScanAt() async {
    final repo = ref.read(appStateRepositoryProvider);
    final raw = await repo.getValue('last_scan_at');
    if (raw == null) return;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null && mounted) {
      ref.read(lastScanAtProvider.notifier).state = parsed;
    }
  }

  /// Runs the startup reconciliation pass once NVAPI reports ready.
  /// Guarded by [_reconciliationStarted] so we don't fire twice if
  /// `NvapiReady` is announced multiple times (initialize() is idempotent
  /// but the provider may re-emit).
  Future<void> _runStartupReconciliation() async {
    if (_reconciliationStarted) return;
    _reconciliationStarted = true;

    ref.read(isReconcilingProvider.notifier).state = true;
    try {
      final service = ref.read(reconciliationServiceProvider);
      final result = await service.reconcile();
      if (!mounted) return;

      ref.read(lastReconciliationProvider.notifier).state = result;

      if (result.hasFatalError) {
        NotificationService.showError(
          'Reconciliation failed.',
          details: result.fatalError,
        );
        return;
      }

      // Hydrate the live-state map from the reconciliation scan so the
      // status dot, toggle, and badge all reflect what's actually on
      // the driver right now — not whatever the local DB last
      // recorded.
      ref
          .read(profileExclusionStateProvider.notifier)
          .setAll({
        for (final entry in result.managedExeLiveValues.entries)
          entry.key: entry.value == null
              ? null
              : entry.value == AppConstants.captureDisableValue,
      });

      // Surface the scan's detected rules into the Detected tab so the
      // user has a one-click path to adopt them (useful right after a
      // local-DB loss).
      ref
          .read(detectedRulesProvider.notifier)
          .setRules(result.detectedExternalRules);

      if (!result.drsResetDetected && result.detectedExternalRules.isNotEmpty) {
        NotificationService.showInfo(
          '${result.detectedExternalRules.length} existing exclusion rule'
          '${result.detectedExternalRules.length == 1 ? '' : 's'} found '
          'outside the app — open the Detected tab to review or adopt.',
        );
      }
    } finally {
      if (mounted) {
        ref.read(isReconcilingProvider.notifier).state = false;
      }
    }

    await _maybeAutoScanOnLaunch();
  }

  /// If the user has enabled "Auto-scan on launch", run a full scan once
  /// reconciliation has settled. Guarded by [_autoScanTriggered] so we
  /// never fire this twice per session — even if reconciliation is rerun.
  Future<void> _maybeAutoScanOnLaunch() async {
    if (_autoScanTriggered) return;
    _autoScanTriggered = true;

    final enabled =
        await ref.read(autoScanOnLaunchProvider.future).catchError((_) => false);
    if (!enabled) return;
    if (!mounted) return;
    if (!_assertNvapiReady()) return;
    await runScan(context, ref);
  }

  void _onSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  bool _assertNvapiReady() {
    final state = ref.read(nvapiProvider);
    if (state is NvapiReady) return true;
    final message = switch (state) {
      NvapiInitializing() =>
        'NVAPI is still initialising — try again in a moment.',
      NvapiError(message: final m) => 'NVAPI unavailable: $m',
      _ => 'NVAPI is not ready yet.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    return false;
  }

  Future<void> _onAddProgram() async {
    if (!_assertNvapiReady()) return;
    final result = await runAddProgramFlow(context, ref);
    if (!mounted) return;
    if (result != null && result.success) {
      final msg = result.exclusionAlreadyApplied
          ? 'Exclusion already applied for ${result.exeName}.'
          : 'Added exclusion for ${result.exeName}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _onScanProfiles() async {
    if (!_assertNvapiReady()) return;
    await runScan(context, ref);
  }

  Future<void> _onBackup() async {
    if (!_assertNvapiReady()) return;
    await showBackupDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final nvapiState = ref.watch(nvapiProvider);

    ref.listen<NvapiState>(nvapiProvider, (prev, next) {
      if (next is NvapiReady) {
        _runStartupReconciliation();
      }
    });

    return Scaffold(
      body: ExeDropTarget(
        child: Column(
          children: [
            AppToolbar(
              onScanProfiles: _onScanProfiles,
              onAddProgram: _onAddProgram,
              onBackup: _onBackup,
              onSettings: _onSettings,
            ),
            if (nvapiState is NvapiError)
              _NvapiBanner(message: nvapiState.message),
            const ReconciliationBanner(),
            const ScanProgressBar(),
            Expanded(
              child: Row(
                // Stretch both panes to the full available height so the
                // right pane's content pins to the top of the pane rather
                // than centering vertically when its intrinsic height is
                // shorter than the row.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    flex: 1,
                    child: LeftPane(onScanProfiles: _onScanProfiles),
                  ),
                  const Flexible(flex: 2, child: RightPane()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NvapiBanner extends StatelessWidget {
  final String message;
  const _NvapiBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.error.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'NVAPI Error: $message',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
