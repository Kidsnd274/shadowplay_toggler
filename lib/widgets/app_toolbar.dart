import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/scan_provider.dart';

class AppToolbar extends ConsumerWidget {
  final VoidCallback? onScanProfiles;
  final VoidCallback? onAddProgram;
  final VoidCallback? onBackup;
  final VoidCallback? onSettings;

  const AppToolbar({
    super.key,
    this.onScanProfiles,
    this.onAddProgram,
    this.onBackup,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isScanning = ref.watch(isScanningProvider);
    final isReconciling = ref.watch(isReconcilingProvider);
    final lastScanAt = ref.watch(lastScanAtProvider);
    // Any NVAPI-touching action must be disabled while a scan or the
    // startup reconciliation pass is running. See [bridgeBusyProvider].
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    // Plan F-45: surface the keyboard shortcuts registered in HomeScreen
    // inside each button's tooltip so the shortcuts are discoverable.
    final scanTooltip = isScanning
        ? 'Scan already in progress'
        : isReconciling
            ? 'Waiting for startup reconciliation to finish'
            : 'Scan every DRS profile for capture-exclusion state '
                '(Ctrl+Shift+S)';
    final busyTooltip = isScanning
        ? 'Wait for the current scan to finish'
        : 'Waiting for startup reconciliation to finish';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title + last-scanned chip on the left. `Expanded` (rather than
          // `Flexible` + `Spacer`) so all the leftover horizontal space is
          // claimed by this child — otherwise the trailing buttons drift
          // away from the right edge when the window is wide because the
          // unfilled portion of a `Flexible` would be left dangling at the
          // end of the row.
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConstants.appTitle,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                if (lastScanAt != null) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Last scanned: ${_formatRelative(lastScanAt)}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isReconciling) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              'Reconciling…',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 12),
          ],
          Tooltip(
            message: scanTooltip,
            child: OutlinedButton.icon(
              onPressed: bridgeBusy ? null : onScanProfiles,
              icon: isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar, size: 18),
              label: Text(isScanning ? 'Scanning…' : 'Scan Profiles'),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: bridgeBusy
                ? busyTooltip
                : 'Add a new program exclusion (Ctrl+N)',
            child: ElevatedButton.icon(
              onPressed: bridgeBusy ? null : onAddProgram,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Program'),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: bridgeBusy
                ? busyTooltip
                : 'Backup / restore NVIDIA DRS settings (Ctrl+B)',
            child: OutlinedButton.icon(
              onPressed: bridgeBusy ? null : onBackup,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Backup'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
