import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../models/rules_export.dart';
import '../providers/database_provider.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/multi_select_provider.dart';
import '../providers/nvidia_defaults_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/rules_export_provider.dart';
import '../providers/scan_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/reset_database_service.dart';
import '../widgets/backup_dialog.dart';
import '../widgets/confirmation_dialog.dart';
import 'logs_screen.dart';

/// Settings hub. Each section is intentionally a self-contained card so
/// new sections can be added without rewiring the others.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _AutoScanSection(),
          SizedBox(height: 12),
          _BackupSection(),
          SizedBox(height: 12),
          _ExportImportSection(),
          SizedBox(height: 12),
          _LogsSection(),
          SizedBox(height: 12),
          _ResetDatabaseSection(),
          SizedBox(height: 12),
          _AboutSection(),
        ],
      ),
    );
  }
}

class _AutoScanSection extends ConsumerWidget {
  const _AutoScanSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncValue = ref.watch(autoScanOnLaunchProvider);

    return _SectionCard(
      icon: Icons.radar,
      title: 'Auto-scan on launch',
      child: asyncValue.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (err, _) => Text(
          'Failed to load setting: $err',
          style: theme.textTheme.bodySmall,
        ),
        data: (enabled) => Row(
          children: [
            Expanded(
              child: Text(
                'When enabled, the app runs Scan Profiles automatically '
                'a few seconds after startup so the Detected and Defaults '
                'tabs are always in sync with the live driver state.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: enabled,
              onChanged: (v) =>
                  ref.read(autoScanOnLaunchProvider.notifier).set(v),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.save_outlined,
      title: 'Backup & Restore',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Snapshot the entire NVIDIA DRS profile database to a file '
            'so you can restore it later if a driver reinstall or any '
            'other change wipes your settings. Restoring overwrites '
            'every DRS setting on the driver, not just exclusions.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => showBackupDialog(context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Backup & Restore'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = ref.watch(isExportingOrImportingRulesProvider);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    final rulesAsync = ref.watch(managedRulesProvider);
    final count = rulesAsync.valueOrNull?.length ?? 0;

    return _SectionCard(
      icon: Icons.import_export,
      title: 'Export / import managed list as JSON',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Save your managed exclusion list to a portable JSON file or '
            're-apply a previously saved list. Importing recreates each '
            'exclusion in the driver and re-populates the Managed list — '
            'handy after a driver reinstall.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'No managed profiles to export yet.'
                : '$count managed profile${count == 1 ? '' : 's'} currently in the list.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: busy || count == 0 ? null : _runExport,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Export to JSON…'),
              ),
              OutlinedButton.icon(
                onPressed: (busy || bridgeBusy) ? null : _runImport,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Import from JSON…'),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runExport() async {
    final picked = await FilePicker.saveFile(
      dialogTitle: 'Export managed profiles',
      fileName: 'shadowplay_rules_${_isoTimestamp()}.json',
      lockParentWindow: true,
    );
    if (picked == null || !mounted) return;

    ref.read(isExportingOrImportingRulesProvider.notifier).state = true;
    try {
      final n =
          await ref.read(rulesExportServiceProvider).exportToFile(picked);
      if (!mounted) return;
      NotificationService.showSuccess(
        'Exported $n rule${n == 1 ? '' : 's'} to ${p.basename(picked)}.',
        context: context,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError('Export failed: $e', context: context);
    } finally {
      if (mounted) {
        ref.read(isExportingOrImportingRulesProvider.notifier).state = false;
      }
    }
  }

  Future<void> _runImport() async {
    if (ref.read(bridgeBusyProvider)) {
      NotificationService.showInfo(
        ref.read(isReconcilingProvider)
            ? 'Startup reconciliation is still running — try again in a moment.'
            : 'A scan is in progress — try again in a moment.',
        context: context,
      );
      return;
    }
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select managed-rules JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      lockParentWindow: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final path = picked.files.single.path;
    if (path == null || !mounted) return;

    ref.read(isExportingOrImportingRulesProvider.notifier).state = true;
    RulesImportResult? result;
    try {
      result =
          await ref.read(rulesExportServiceProvider).importFromFile(path);
    } on FormatException catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        'Import failed: ${e.message}',
        context: context,
      );
      return;
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError('Import failed: $e', context: context);
      return;
    } finally {
      if (mounted) {
        ref.read(isExportingOrImportingRulesProvider.notifier).state = false;
      }
    }

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;

    final summary = _summariseImport(result);
    if (result.hasFailures) {
      NotificationService.showError(
        summary,
        context: context,
        details: result.errors.join('\n'),
      );
    } else if (result.hasSkips || result.alreadyManaged > 0) {
      NotificationService.showWarning(summary, context: context);
    } else {
      NotificationService.showSuccess(summary, context: context);
    }
  }
}

class _LogsSection extends StatelessWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.terminal,
      title: 'Logs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'View the in-process log buffer — the same lines you would see '
            'in the terminal during a `flutter run`. Useful when reporting '
            'a bug or chasing down an unexpected error.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                );
              },
              icon: const Icon(Icons.subject, size: 16),
              label: const Text('View Logs'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetDatabaseSection extends ConsumerStatefulWidget {
  const _ResetDatabaseSection();

  @override
  ConsumerState<_ResetDatabaseSection> createState() =>
      _ResetDatabaseSectionState();
}

class _ResetDatabaseSectionState
    extends ConsumerState<_ResetDatabaseSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return _SectionCard(
      icon: Icons.warning_amber_rounded,
      iconColor: theme.colorScheme.error,
      title: 'Reset database',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wipes this app\'s local database — every profile in your '
            'Managed list and every saved preference. The NVIDIA driver '
            'is NOT touched: existing exclusions on the driver stay in '
            'place and will reappear in the Detected tab on the next '
            'scan. Use this if the local list has gotten out of sync '
            'with the driver and you want a clean slate.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: (_busy || bridgeBusy) ? null : _onResetPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined, size: 16),
              label: const Text('Reset Database…'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onResetPressed() async {
    if (ref.read(bridgeBusyProvider)) {
      NotificationService.showInfo(
        ref.read(isReconcilingProvider)
            ? 'Startup reconciliation is still running — try again in a moment.'
            : 'A scan is in progress — try again in a moment.',
        context: context,
      );
      return;
    }

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Reset local database?',
      message: 'This deletes every row in your Managed list and every '
          'saved preference. Existing NVIDIA driver exclusions are not '
          'touched and can be re-adopted via the Detected tab after the '
          'next scan. This cannot be undone.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(resetDatabaseServiceProvider).reset();
      if (!mounted) return;

      // Clear every in-memory surface that referenced the now-gone rows.
      // Anything that holds an id/exePath the user selected or a scan
      // snapshot taken before the wipe has to be discarded, otherwise
      // the UI will render phantom rows (and crash if the user clicks
      // one) until the next reconciliation round-trips.
      ref.read(detectedRulesProvider.notifier).clear();
      ref.read(nvidiaDefaultsProvider.notifier).clear();
      ref.read(profileExclusionStateProvider.notifier).setAll(const {});
      ref.read(selectedRuleProvider.notifier).state = null;
      exitMultiSelect(ref);
      ref.read(lastScanResultProvider.notifier).state = null;
      ref.read(lastScanAtProvider.notifier).state = null;
      ref.read(lastReconciliationProvider.notifier).state = null;
      await ref.read(managedRulesProvider.notifier).refresh();

      // The auto-scan toggle is loaded from the now-empty app_state
      // table — nudge the provider to re-read so the Settings screen
      // reflects the cleared value.
      ref.invalidate(autoScanOnLaunchProvider);

      if (!mounted) return;
      NotificationService.showSuccess(
        'Local database reset.',
        context: context,
      );
    } on ResetDatabaseException catch (e) {
      if (!mounted) return;
      NotificationService.showError(e.message, context: context);
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        'Reset failed: $e',
        context: context,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.info_outline,
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.appTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Per-application NVIDIA ShadowPlay / Instant Replay capture '
            'exclusion manager.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _AboutRow(
            label: 'Capture setting',
            value: '0x${AppConstants.captureSettingId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
          ),
          _AboutRow(
            label: 'Platform',
            value: '${Platform.operatingSystem} '
                '${Platform.operatingSystemVersion}',
          ),
          _AboutRow(label: 'Dart version', value: Platform.version),
          const SizedBox(height: 12),
          Text(
            'NVIDIA driver settings are read and written via NVAPI. '
            'This app never collects or transmits any data — every '
            'operation is local to your machine.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String _isoTimestamp() {
  String two(int v) => v.toString().padLeft(2, '0');
  final now = DateTime.now();
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String _summariseImport(RulesImportResult r) {
  final parts = <String>[];
  if (r.imported > 0) parts.add('${r.imported} added');
  if (r.alreadyManaged > 0) parts.add('${r.alreadyManaged} already managed');
  if (r.skippedMissingFile > 0) {
    parts.add('${r.skippedMissingFile} skipped (file missing)');
  }
  if (r.failed > 0) parts.add('${r.failed} failed');
  if (parts.isEmpty) return 'Nothing to import (file had no rules).';
  return 'Import finished: ${parts.join(', ')}.';
}
