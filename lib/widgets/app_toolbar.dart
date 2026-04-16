import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
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
    final lastScanAt = ref.watch(lastScanAtProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Row(
        children: [
          // Left-hand title + last-scanned chip. Wrapped in a Flexible so the
          // secondary "Last scanned" line can ellipsize at narrow widths
          // instead of pushing the right-side buttons into overflow
          // territory (which manifested as sub-pixel RenderFlex errors).
          Flexible(
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
          const SizedBox(width: 12),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: isScanning ? null : onScanProfiles,
            icon: isScanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar, size: 18),
            label: Text(isScanning ? 'Scanning…' : 'Scan Profiles'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onAddProgram,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Program'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onBackup,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Backup'),
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
