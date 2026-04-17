import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/nvidia_defaults_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/scan_provider.dart';
import '../services/notification_service.dart';

/// App-state key for persisting the last-scan timestamp across sessions.
const _kLastScanAtKey = 'last_scan_at';

/// Orchestrates the full scan → classify → publish-to-providers flow
/// described in `plans/23-scan-profiles-feature.md`.
///
/// Call this from the toolbar "Scan Profiles" button.
Future<void> runScan(BuildContext context, WidgetRef ref) async {
  if (ref.read(isScanningProvider)) return;
  ref.read(isScanningProvider.notifier).state = true;

  final service = ref.read(scanServiceProvider);

  try {
    final result = await service.scanProfiles();
    if (result.hasError) {
      if (!context.mounted) return;
      NotificationService.showError(
        'Scan failed: ${result.error}',
        context: context,
      );
      return;
    }

    ref.read(detectedRulesProvider.notifier).setRules(result.detectedRules);
    ref.read(nvidiaDefaultsProvider.notifier).setRules(result.nvidiaDefaults);
    ref.read(lastScanResultProvider.notifier).state = result;

    // The scan walked every DRS profile we care about — push the live
    // exclusion state for each watched exe into the global state map so
    // the status dot, toggle and badge all reflect the freshly-observed
    // truth.
    ref.read(profileExclusionStateProvider.notifier).hydrateFromScan(result);

    // Refresh managed rules so drift/orphan badges re-render against the
    // freshly populated providers.
    await ref.read(managedRulesProvider.notifier).refresh();

    final now = DateTime.now();
    ref.read(lastScanAtProvider.notifier).state = now;
    unawaited(ref
        .read(appStateRepositoryProvider)
        .setValue(_kLastScanAtKey, now.toIso8601String()));

    if (!context.mounted) return;
    final message = 'Scan complete: ${result.detectedRules.length} external, '
        '${result.nvidiaDefaults.length} defaults '
        '(${result.scanDuration.inMilliseconds} ms).';
    // Surface non-fatal native warnings (plan F-19). These come from
    // profiles where GetSetting failed for a non-"not-found" reason —
    // the scan still produced a result, but the user should know some
    // rows may be incomplete.
    if (result.warnings.isNotEmpty) {
      NotificationService.showWarning(
        '$message ${result.warnings.length} warning'
        '${result.warnings.length == 1 ? '' : 's'} — check Logs.',
        context: context,
      );
    } else {
      NotificationService.showSuccess(message, context: context);
    }
  } finally {
    ref.read(isScanningProvider.notifier).state = false;
  }
}

/// Indeterminate progress bar shown under the toolbar while a scan is
/// running. Debounced by 150 ms so fast scans don't flash the indicator.
class ScanProgressBar extends ConsumerStatefulWidget {
  const ScanProgressBar({super.key});

  @override
  ConsumerState<ScanProgressBar> createState() => _ScanProgressBarState();
}

class _ScanProgressBarState extends ConsumerState<ScanProgressBar> {
  Timer? _debounceTimer;
  Timer? _longScanTimer;
  bool _showIndicator = false;
  bool _longScanMessage = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _longScanTimer?.cancel();
    super.dispose();
  }

  void _onScanningChanged(bool isScanning) {
    _debounceTimer?.cancel();
    _longScanTimer?.cancel();

    if (isScanning) {
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _showIndicator = true);
      });
      _longScanTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _longScanMessage = true);
      });
    } else {
      if (_showIndicator || _longScanMessage) {
        setState(() {
          _showIndicator = false;
          _longScanMessage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isScanningProvider, (prev, next) {
      _onScanningChanged(next);
    });

    if (!_showIndicator) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        if (_longScanMessage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Scanning NVIDIA profiles — this is taking a while.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
