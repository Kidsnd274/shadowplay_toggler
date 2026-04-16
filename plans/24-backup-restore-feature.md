# 24 - Backup and Restore Feature

## Goal

Implement the UI and service layer for backing up and restoring NVIDIA DRS settings.

## Prerequisites

- Plan 12 (Dart FFI Bindings) completed (backup/restore FFI functions).
- Plan 14 (App Shell Layout) completed (toolbar "Backup" button exists).

## Background

From `design.md`: Before making the first driver modification, the app should offer a full driver-profile backup. NVAPI exposes save/load-from-file APIs. This is a critical safety feature.

## Tasks

1. **Create `lib/services/backup_service.dart`**
   - Methods:
     ```dart
     Future<String> createBackup({String? customPath});
     Future<void> restoreBackup(String filePath);
     Future<List<BackupInfo>> listBackups();
     Future<void> deleteBackup(String filePath);
     ```
   - Default backup location: `%APPDATA%/ShadowPlayToggler/backups/`
   - Backup filename format: `drs_backup_YYYYMMDD_HHMMSS.nvidiaprofile`
   - `createBackup` calls `nvapiService.exportSettings(filePath)`.
   - `restoreBackup` calls `nvapiService.importSettings(filePath)`.

2. **Create `lib/models/backup_info.dart`**
   ```dart
   class BackupInfo {
     final String filePath;
     final String fileName;
     final DateTime createdAt;
     final int fileSizeBytes;
   }
   ```

3. **Build the backup dialog**
   - Create `lib/widgets/backup_dialog.dart`.
   - Opened from the toolbar "Backup" button.
   - Dialog contents:
     - "Create Backup" section:
       - "Export current DRS settings to a backup file."
       - [Create Backup] button.
       - Option to choose custom save location (file picker).
     - "Restore from Backup" section:
       - "Restore DRS settings from a previous backup."
       - [Select Backup File] button (file picker).
       - **Warning**: "This will overwrite your current driver profile settings. A backup of the current state will be created automatically before restoring."
       - Confirmation required before restoring.
     - "Previous Backups" section:
       - List of existing backups in the default location.
       - Each entry shows: filename, date, size.
       - Actions: Restore, Delete, Open folder.

4. **Implement auto-backup before first write**
   - In the "Add Program" flow (plan 21), before the first-ever driver modification:
     - Check app state for `first_backup_done`.
     - If false, show a dialog: "Before making changes, we recommend creating a backup of your current driver settings."
     - [Create Backup and Continue] [Skip] [Cancel]
     - If the user creates a backup, set `first_backup_done = true`.

5. **Implement auto-backup before restore**
   - Before restoring from a backup file, automatically create a backup of the current state.
   - This ensures the user can always undo a restore.

6. **Wire up the toolbar button**
   - Connect "Backup" button to open the backup dialog.

7. **Add backup-related providers**
   - `backupListProvider` - lists available backups.
   - `isBackingUpProvider` - tracks backup/restore in progress.

## Acceptance Criteria

- Users can create backups that are saved to the default location.
- Users can restore from a backup file with confirmation.
- Auto-backup is offered before the first driver modification.
- Auto-backup is created before any restore operation.
- Previous backups are listed with dates and sizes.
- Backup files can be deleted from the app.
- Error handling for file I/O and NVAPI failures.
- `flutter analyze` reports no errors.
