import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/backup_info.dart';
import '../models/rules_export.dart';
import '../providers/backup_provider.dart';
import '../providers/database_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/rules_export_provider.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';

/// Entry point for the Backup / Restore dialog.
///
/// The dialog covers three surfaces described in
/// `plans/24-backup-restore-feature.md`:
///   - Create Backup (default or custom path)
///   - Restore from Backup (with required confirmation + auto-backup)
///   - Previous Backups list (restore / delete / open folder)
Future<void> showBackupDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _BackupDialog(),
  );
}

/// Shared backstop for every backup/restore/delete action. The dialog's
/// buttons already grey out via [bridgeBusyProvider], but guard racy
/// paths (keyboard, dialog pre-select) from entering the shared bridge
/// session while a scan or startup reconciliation is running. See plan
/// F-16.
bool _assertBridgeFree(BuildContext context, WidgetRef ref) {
  if (!ref.read(bridgeBusyProvider)) return true;
  final reconciling = ref.read(isReconcilingProvider);
  final msg = reconciling
      ? 'Startup reconciliation is still running — try again in a moment.'
      : 'A scan is in progress — try again in a moment.';
  NotificationService.showInfo(msg, context: context);
  return false;
}

/// Called by the Add Program flow before its first driver write.
///
/// Behaviour:
///   1. Checks `first_backup_done` in the app-state DB. If already set, the
///      helper returns `true` without prompting.
///   2. Otherwise shows a dialog with three options:
///        - Create Backup and Continue: creates a backup, flags done,
///          returns true.
///        - Skip: flags done, returns true.
///        - Cancel: returns false (caller aborts the write).
Future<bool> offerFirstBackupIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final appState = ref.read(appStateRepositoryProvider);
  final already = await appState.getBool(kFirstBackupDoneKey);
  if (already) return true;
  if (!context.mounted) return false;
  if (!_assertBridgeFree(context, ref)) return false;

  final choice = await showDialog<_FirstBackupDecision>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _FirstBackupPrompt(),
  );

  switch (choice) {
    case _FirstBackupDecision.backupAndContinue:
      ref.read(isBackingUpProvider.notifier).state = true;
      try {
        final path =
            await ref.read(backupServiceProvider).createBackup();
        await ref.read(backupListProvider.notifier).refresh();
        if (context.mounted) {
          NotificationService.showSuccess(
            'Backup saved to ${p.basename(path)}',
            context: context,
          );
        }
      } on BackupServiceException catch (e) {
        if (context.mounted) {
          NotificationService.showError(e.message, context: context);
        }
        return false;
      } finally {
        ref.read(isBackingUpProvider.notifier).state = false;
      }
      await appState.setBool(kFirstBackupDoneKey, true);
      return true;
    case _FirstBackupDecision.skip:
      await appState.setBool(kFirstBackupDoneKey, true);
      return true;
    case _FirstBackupDecision.cancel:
    case null:
      return false;
  }
}

enum _FirstBackupDecision { backupAndContinue, skip, cancel }

class _BackupDialog extends ConsumerWidget {
  const _BackupDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(isBackingUpProvider);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      // Fixed-size SizedBox (capped by MediaQuery if the window is
      // shorter than 680px) gives the dialog a stable footprint so it
      // doesn't grow/shrink every time an async section finishes
      // loading. Combined with Expanded below, the scroll view always
      // fills the remaining vertical space instead of fighting a
      // Flexible + SingleChildScrollView intrinsic-size measurement.
      // Plan F-31.
      child: SizedBox(
        width: 640,
        height: _dialogHeight(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.save_outlined),
                  const SizedBox(width: 8),
                  Text('Backup & Restore',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed:
                        busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      _CreateBackupSection(),
                      SizedBox(height: 16),
                      _RestoreSection(),
                      SizedBox(height: 16),
                      _RulesExportImportSection(),
                      SizedBox(height: 16),
                      _PreviousBackupsSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 680px on tall windows, less on short ones (with a 48px margin to
  /// match [Dialog.insetPadding]). Prevents overflow on laptop
  /// displays where the default 680 would push the dialog off-screen.
  double _dialogHeight(BuildContext context) {
    const preferred = 680.0;
    final available = MediaQuery.of(context).size.height - 48;
    return available < preferred ? available : preferred;
  }
}

class _CreateBackupSection extends ConsumerWidget {
  const _CreateBackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(isBackingUpProvider);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    final locked = busy || bridgeBusy;

    return _SectionCard(
      title: 'Create backup',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export current NVIDIA DRS settings to a backup file. Use this '
            'before making changes so you can restore the previous state if '
            'anything goes wrong.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: locked ? null : () => _runCreate(context, ref),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Create Backup'),
              ),
              OutlinedButton.icon(
                onPressed:
                    locked ? null : () => _runCreateCustom(context, ref),
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Save to…'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runCreate(BuildContext context, WidgetRef ref) async {
    if (!_assertBridgeFree(context, ref)) return;
    await _performCreate(context, ref, customPath: null);
  }

  Future<void> _runCreateCustom(BuildContext context, WidgetRef ref) async {
    if (!_assertBridgeFree(context, ref)) return;
    final suggestedName = p.basename(
      await ref.read(backupServiceProvider).defaultBackupDirectory(),
    );
    if (!context.mounted) return;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: 'drs_backup_${_timestamp()}.nvidiaProfileInspector',
      initialDirectory: suggestedName,
      lockParentWindow: true,
    );
    if (path == null) return;
    if (!context.mounted) return;
    await _performCreate(context, ref, customPath: path);
  }

  Future<void> _performCreate(
    BuildContext context,
    WidgetRef ref, {
    required String? customPath,
  }) async {
    ref.read(isBackingUpProvider.notifier).state = true;
    try {
      final service = ref.read(backupServiceProvider);
      final path = await service.createBackup(customPath: customPath);
      if (customPath == null) {
        await ref.read(backupListProvider.notifier).refresh();
      }
      if (!context.mounted) return;
      NotificationService.showSuccess(
        'Backup saved to ${p.basename(path)}',
        context: context,
      );
    } on BackupServiceException catch (e) {
      if (!context.mounted) return;
      NotificationService.showError(e.message, context: context);
    } catch (e) {
      if (!context.mounted) return;
      NotificationService.showError('Backup failed: $e', context: context);
    } finally {
      ref.read(isBackingUpProvider.notifier).state = false;
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

class _RestoreSection extends ConsumerWidget {
  const _RestoreSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(isBackingUpProvider);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    final locked = busy || bridgeBusy;

    return _SectionCard(
      title: 'Restore from backup',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replace your current DRS settings with a previously saved '
            'backup. The current state is automatically backed up first so '
            'you can always undo.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This will overwrite ALL of your current NVIDIA DRS '
                    'settings — not just capture exclusions.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: locked ? null : () => _pickAndRestore(context, ref),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Select Backup File…'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndRestore(BuildContext context, WidgetRef ref) async {
    if (!_assertBridgeFree(context, ref)) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select backup file',
      type: FileType.any,
      lockParentWindow: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;

    await confirmAndRestoreBackup(context, ref, path);
  }
}

/// Runs the confirmation dialog, auto-backup, and restore flow for a
/// chosen backup file. Reused by both the "Select Backup File…" button
/// and the per-row "Restore" action.
Future<void> confirmAndRestoreBackup(
  BuildContext context,
  WidgetRef ref,
  String filePath,
) async {
  if (!_assertBridgeFree(context, ref)) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore backup?'),
      content: Text(
        'This will overwrite your current NVIDIA driver profile settings '
        'with the contents of ${p.basename(filePath)}.\n\n'
        'A backup of the current state will be created automatically first.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  ref.read(isBackingUpProvider.notifier).state = true;
  final service = ref.read(backupServiceProvider);
  try {
    final autoBackupPath = await service.createBackup();
    await service.restoreBackup(filePath);
    await ref.read(backupListProvider.notifier).refresh();
    if (!context.mounted) return;
    NotificationService.showSuccess(
      'Restored from ${p.basename(filePath)}. '
      'Pre-restore backup: ${p.basename(autoBackupPath)}.',
      context: context,
    );
  } on BackupServiceException catch (e) {
    if (!context.mounted) return;
    NotificationService.showError(e.message, context: context);
  } catch (e) {
    if (!context.mounted) return;
    NotificationService.showError('Restore failed: $e', context: context);
  } finally {
    ref.read(isBackingUpProvider.notifier).state = false;
  }
}

class _PreviousBackupsSection extends ConsumerWidget {
  const _PreviousBackupsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final backupsAsync = ref.watch(backupListProvider);

    return _SectionCard(
      title: 'Previous backups',
      body: backupsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => Text(
          'Failed to list backups: $err',
          style: theme.textTheme.bodySmall,
        ),
        data: (backups) {
          if (backups.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No backups yet.',
                style: theme.textTheme.bodySmall,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in backups) _BackupRow(info: b),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final dir = await ref
                          .read(backupServiceProvider)
                          .defaultBackupDirectory();
                      if (dir.isEmpty) return;
                      _openFolder(dir);
                    },
                    icon: const Icon(Icons.folder, size: 16),
                    label: const Text('Open backups folder'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(backupListProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BackupRow extends ConsumerWidget {
  final BackupInfo info;
  const _BackupRow({required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(isBackingUpProvider);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    final restoreLocked = busy || bridgeBusy;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.fileName, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(info.createdAt)}  •  ${info.humanSize}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore this backup',
            onPressed: restoreLocked
                ? null
                : () => confirmAndRestoreBackup(context, ref, info.filePath),
            icon: const Icon(Icons.restore, size: 18),
          ),
          IconButton(
            tooltip: 'Delete backup',
            onPressed: busy ? null : () => _confirmDelete(context, ref, info),
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BackupInfo info,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete backup?'),
        content: Text('Delete ${info.fileName}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(backupServiceProvider).deleteBackup(info.filePath);
    await ref.read(backupListProvider.notifier).refresh();
  }
}

class _RulesExportImportSection extends ConsumerWidget {
  const _RulesExportImportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(isExportingOrImportingRulesProvider);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    final rulesAsync = ref.watch(managedRulesProvider);
    final count = rulesAsync.valueOrNull?.length ?? 0;
    final importLocked = busy || bridgeBusy;

    return _SectionCard(
      title: 'Export / import managed profiles',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Save your managed exclusion list to a JSON file, or re-apply a '
            'previously saved list. Useful after a driver reinstall wipes '
            "NVIDIA's profiles — importing re-creates each exclusion in the "
            'driver and the managed list in one click.',
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
            children: [
              ElevatedButton.icon(
                onPressed: busy || count == 0
                    ? null
                    : () => _runExport(context, ref),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Export to JSON…'),
              ),
              OutlinedButton.icon(
                onPressed:
                    importLocked ? null : () => _runImport(context, ref),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Import from JSON…'),
              ),
              if (busy) ...[
                const SizedBox(width: 4),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runExport(BuildContext context, WidgetRef ref) async {
    final suggested = 'shadowplay_rules_${_isoTimestamp()}.json';
    final picked = await FilePicker.saveFile(
      dialogTitle: 'Export managed profiles',
      fileName: suggested,
      lockParentWindow: true,
    );
    if (picked == null) return;
    if (!context.mounted) return;

    ref.read(isExportingOrImportingRulesProvider.notifier).state = true;
    try {
      final count =
          await ref.read(rulesExportServiceProvider).exportToFile(picked);
      if (!context.mounted) return;
      NotificationService.showSuccess(
        'Exported $count rule${count == 1 ? '' : 's'} to ${p.basename(picked)}.',
        context: context,
      );
    } catch (e) {
      if (!context.mounted) return;
      NotificationService.showError(
        'Export failed: $e',
        context: context,
      );
    } finally {
      ref.read(isExportingOrImportingRulesProvider.notifier).state = false;
    }
  }

  Future<void> _runImport(BuildContext context, WidgetRef ref) async {
    if (!_assertBridgeFree(context, ref)) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select managed-rules JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      lockParentWindow: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;

    ref.read(isExportingOrImportingRulesProvider.notifier).state = true;
    RulesImportResult? result;
    try {
      result =
          await ref.read(rulesExportServiceProvider).importFromFile(path);
    } on FormatException catch (e) {
      if (!context.mounted) return;
      NotificationService.showError(
        'Import failed: ${e.message}',
        context: context,
      );
      return;
    } catch (e) {
      if (!context.mounted) return;
      NotificationService.showError(
        'Import failed: $e',
        context: context,
      );
      return;
    } finally {
      ref.read(isExportingOrImportingRulesProvider.notifier).state = false;
    }

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!context.mounted) return;

    final summary = _summarise(result);
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

  String _summarise(RulesImportResult r) {
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

  String _isoTimestamp() {
    final now = DateTime.now();
    two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget body;

  const _SectionCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

class _FirstBackupPrompt extends StatelessWidget {
  const _FirstBackupPrompt();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a backup first?'),
      content: const Text(
        "Before ShadowPlay Toggler modifies any driver settings, we "
        "recommend creating a backup of your current NVIDIA DRS "
        "profiles so you can restore them if anything goes wrong.\n\n"
        "This is a one-time prompt.",
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_FirstBackupDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_FirstBackupDecision.skip),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(_FirstBackupDecision.backupAndContinue),
          child: const Text('Create Backup and Continue'),
        ),
      ],
    );
  }
}

String _formatDate(DateTime dt) {
  two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

Future<void> _openFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    }
  } catch (_) {
    // Non-fatal; user can navigate manually if needed.
  }
}
