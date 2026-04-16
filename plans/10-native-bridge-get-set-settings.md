# 10 - Native Bridge: Get/Set/Delete/Restore Settings

## Goal

Implement the core DRS setting operations: reading, writing, deleting, and restoring settings on profiles. This is the heart of the exclusion functionality.

## Prerequisites

- Plan 07 (DRS Session Management) completed.
- Plan 08 (Enumerate Profiles) completed for profile handle access.

## Background

The key NVAPI functions are:
- `NvAPI_DRS_GetSetting` - Read a setting value from a profile
- `NvAPI_DRS_SetSetting` - Write a setting value to a profile
- `NvAPI_DRS_DeleteProfileSetting` - Remove a setting override from a profile
- `NvAPI_DRS_RestoreProfileDefault` - Restore all settings in a profile to defaults
- `NvAPI_DRS_RestoreProfileDefaultSetting` - Restore a single setting to default

The target setting is `0x809D5F60` and the exclusion value is `0x10000000`.

Settings have a type (DWORD, string, binary, etc.). Our target is a DWORD setting.

## Tasks

1. **Implement `bridge_get_setting()`**
   ```cpp
   BRIDGE_API const char* bridge_get_setting(int profileIndex, unsigned int settingId);
   ```
   - Get the specified setting from the profile at the given index.
   - Return JSON:
     ```json
     {
       "found": true,
       "settingId": "0x809D5F60",
       "currentValue": "0x10000000",
       "predefinedValue": "0x00000000",
       "isCurrentPredefined": false,
       "settingLocation": "current_profile"
     }
     ```
   - If the setting is not present in the profile, return `{"found": false}`.

2. **Implement `bridge_set_dword_setting()`**
   ```cpp
   BRIDGE_API int bridge_set_dword_setting(int profileIndex, unsigned int settingId, unsigned int value);
   ```
   - Set a DWORD setting on the specified profile.
   - Fill in `NVDRS_SETTING` struct with the setting ID, type = DWORD, and the value.
   - Call `NvAPI_DRS_SetSetting`.
   - Return 0 on success, negative error code on failure.
   - Does NOT call `NvAPI_DRS_SaveSettings` — the caller must save explicitly.

3. **Implement `bridge_delete_setting()`**
   ```cpp
   BRIDGE_API int bridge_delete_setting(int profileIndex, unsigned int settingId);
   ```
   - Remove the setting override from the profile.
   - Call `NvAPI_DRS_DeleteProfileSetting`.
   - Return 0 on success, negative on failure.

4. **Implement `bridge_restore_setting_default()`**
   ```cpp
   BRIDGE_API int bridge_restore_setting_default(int profileIndex, unsigned int settingId);
   ```
   - Restore a single setting to its NVIDIA default.
   - Call `NvAPI_DRS_RestoreProfileDefaultSetting`.
   - Return 0 on success, negative on failure.

5. **Implement `bridge_apply_exclusion()`** (convenience function)
   ```cpp
   BRIDGE_API int bridge_apply_exclusion(const char* exePath);
   ```
   - High-level function that:
     1. Finds or creates a profile for the given exe
     2. Adds the application to the profile if needed
     3. Sets `0x809D5F60` = `0x10000000`
     4. Saves settings
   - Returns JSON with the result:
     ```json
     {
       "success": true,
       "profileName": "obs64.exe",
       "created": true,
       "settingApplied": true
     }
     ```

6. **Implement `bridge_create_profile()`** (helper for apply_exclusion)
   ```cpp
   BRIDGE_API int bridge_create_profile(const char* profileName);
   ```
   - Create a new user profile with the given name.
   - Use `NvAPI_DRS_CreateProfile`.
   - Return 0 on success.

7. **Implement `bridge_add_application()`** (helper for apply_exclusion)
   ```cpp
   BRIDGE_API int bridge_add_application(int profileIndex, const char* exePath);
   ```
   - Add an application entry to a profile.
   - Use `NvAPI_DRS_CreateApplication`.
   - Return 0 on success.

8. **Update `native/bridge.h`** with all new declarations.

## Acceptance Criteria

- Can read setting `0x809D5F60` from any profile and get the correct value.
- Can write the exclusion value (`0x10000000`) to a profile.
- Can delete a setting override.
- Can restore a setting to its default.
- `bridge_apply_exclusion()` handles the full create-or-update flow.
- All changes persist after `bridge_save_settings()`.
- Error codes are meaningful and consistent.
