# 09 - Native Bridge: Enumerate Applications

## Goal

Implement application enumeration within NVIDIA DRS profiles, so Dart can discover which executables are associated with each profile.

## Prerequisites

- Plan 08 (Enumerate Profiles) completed.

## Background

Each DRS profile can have zero or more associated applications. NVAPI provides:
- `NvAPI_DRS_EnumApplications` to list apps in a profile
- `NvAPI_DRS_FindApplicationByName` to look up an app by executable name
- `NvAPI_DRS_GetApplicationInfo` to get details about a specific app

Application entries contain:
- App name (usually the executable filename)
- Friendly name
- Launcher name
- File in folder (for folder-based matching)
- Whether the entry is predefined

## Tasks

1. **Implement `bridge_get_profile_apps_json()`**
   ```cpp
   BRIDGE_API const char* bridge_get_profile_apps_json(int profileIndex);
   ```
   - Given a profile index, enumerate all applications in that profile.
   - Return JSON array:
     ```json
     [
       {
         "appName": "obs64.exe",
         "friendlyName": "OBS Studio 64bit",
         "launcher": "",
         "isPredefined": false
       },
       ...
     ]
     ```
   - Convert wide strings to UTF-8.

2. **Implement `bridge_find_application()`**
   ```cpp
   BRIDGE_API const char* bridge_find_application(const char* exePath);
   ```
   - Given an executable path (UTF-8), call `NvAPI_DRS_FindApplicationByName`.
   - If found, return JSON with the app info and its parent profile info:
     ```json
     {
       "found": true,
       "appName": "obs64.exe",
       "profileName": "OBS Studio",
       "isPredefined": false,
       "profileIsPredefined": true
     }
     ```
   - If not found, return `{"found": false}`.
   - Convert the input UTF-8 path to wide string for the NVAPI call.

3. **Implement `bridge_get_base_profile_handle()`**
   ```cpp
   BRIDGE_API int bridge_get_base_profile_handle();
   ```
   - Use `NvAPI_DRS_GetBaseProfile` to get the base profile handle.
   - Store it internally for use by other functions.
   - Return 0 on success, negative on failure.

4. **Update `native/bridge.h`** with all new declarations.

## Acceptance Criteria

- `bridge_get_profile_apps_json()` returns correct app lists for any profile.
- `bridge_find_application()` correctly finds or reports missing executables.
- Wide string to UTF-8 conversion works for international characters.
- Empty profiles return an empty JSON array `[]`.
- All returned JSON strings can be freed with `bridge_free_json()`.
