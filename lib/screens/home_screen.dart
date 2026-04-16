import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nvapi_state.dart';
import '../providers/database_provider.dart';
import '../providers/nvapi_provider.dart';
import '../providers/scan_provider.dart';
import '../widgets/add_program_dialog.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/backup_dialog.dart';
import '../widgets/exe_drop_target.dart';
import '../widgets/left_pane.dart';
import '../widgets/right_pane.dart';
import '../widgets/scan_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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

  void _showNotImplemented(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — not implemented yet'),
        duration: const Duration(seconds: 2),
      ),
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

    return Scaffold(
      body: ExeDropTarget(
        child: Column(
          children: [
            AppToolbar(
              onScanProfiles: _onScanProfiles,
              onAddProgram: _onAddProgram,
              onBackup: _onBackup,
              onSettings: () => _showNotImplemented('Settings'),
            ),
            if (nvapiState is NvapiError)
              _NvapiBanner(message: nvapiState.message),
            const ScanProgressBar(),
            Expanded(
              child: Row(
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
