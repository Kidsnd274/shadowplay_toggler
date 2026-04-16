# 11 - Native Bridge: Backup and Restore

## Goal

Implement DRS settings backup (export) and restore (import) functionality in the native bridge.

## Prerequisites

- Plan 07 (DRS Session Management) completed.

## Background

NVAPI provides:
- `NvAPI_DRS_SaveSettingsToFile` - Export the entire DRS database to a file
- `NvAPI_DRS_LoadSettingsFromFile` - Import DRS database from a file

These are critical safety features. The app should offer a backup before making any driver modifications.

## Tasks

1. **Implement `bridge_export_settings()`**
   ```cpp
   BRIDGE_API int bridge_export_settings(const char* filePath);
   ```
   - Convert the UTF-8 file path to a wide string.
   - Call `NvAPI_DRS_SaveSettingsToFile(g_session, wideFilePath)`.
   - Return 0 on success, negative error code on failure.

2. **Implement `bridge_import_settings()`**
   ```cpp
   BRIDGE_API int bridge_import_settings(const char* filePath);
   ```
   - Convert the UTF-8 file path to a wide string.
   - Call `NvAPI_DRS_LoadSettingsFromFile(g_session, wideFilePath)`.
   - After loading, call `NvAPI_DRS_SaveSettings` to persist.
   - Return 0 on success, negative error code on failure.
   - **Important**: This overwrites current driver settings. The UI layer should confirm with the user before calling this.

3. **Add utility: `bridge_get_default_backup_path()`**
   ```cpp
   BRIDGE_API const char* bridge_get_default_backup_path();
   ```
   - Return a suggested backup file path, e.g., `%APPDATA%/ShadowPlayToggler/backups/drs_backup_YYYYMMDD_HHMMSS.nvidiaProfileInspector` or similar.
   - Create the directory if it does not exist.

4. **Update `native/bridge.h`** with all new declarations.

## Acceptance Criteria

- `bridge_export_settings()` creates a valid backup file at the specified path.
- `bridge_import_settings()` restores settings from a backup file.
- File paths with spaces and Unicode characters work correctly.
- Error codes are returned for invalid paths or NVAPI failures.
- The backup file can be imported by NVIDIA Profile Inspector as a cross-check.
