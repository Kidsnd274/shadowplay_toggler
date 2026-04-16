# 08 - Native Bridge: Enumerate Profiles

## Goal

Implement profile enumeration in the native bridge so Dart can get a list of all NVIDIA DRS profiles.

## Prerequisites

- Plan 07 (DRS Session Management) completed.

## Background

NVAPI provides `NvAPI_DRS_EnumProfiles` to iterate through all profiles in a session, and `NvAPI_DRS_GetProfileInfo` to get details about each profile. Profiles contain:
- Profile name (wide string)
- Number of associated applications
- Number of settings
- Whether the profile is predefined by NVIDIA or user-created
- GPU support flags

## Tasks

1. **Define a C-compatible profile info struct**
   ```cpp
   typedef struct {
       char profileName[256];  // UTF-8 converted from wide string
       int numApplications;
       int numSettings;
       int isPredefined;       // 1 = predefined, 0 = user-created
       unsigned int profileHandle; // opaque, for internal use
   } BridgeProfileInfo;
   ```

2. **Implement `bridge_get_profile_count()`**
   ```cpp
   BRIDGE_API int bridge_get_profile_count();
   ```
   - Use `NvAPI_DRS_EnumProfiles` in a loop to count all profiles.
   - Return the count, or a negative error code on failure.

3. **Implement `bridge_get_profile_info()`**
   ```cpp
   BRIDGE_API int bridge_get_profile_info(int index, BridgeProfileInfo* out);
   ```
   - Enumerate to the given index using `NvAPI_DRS_EnumProfiles`.
   - Fill the `BridgeProfileInfo` struct.
   - Convert the wide string profile name to UTF-8.
   - Return 0 on success, negative error code on failure.

4. **Implement `bridge_get_all_profiles_json()`** (alternative/simpler approach)
   ```cpp
   BRIDGE_API const char* bridge_get_all_profiles_json();
   ```
   - Enumerate all profiles and return a JSON string with all profile info.
   - JSON format:
     ```json
     [
       {
         "name": "Base Profile",
         "numApplications": 0,
         "numSettings": 42,
         "isPredefined": true,
         "index": 0
       },
       ...
     ]
     ```
   - Store in a static string buffer that Dart can read.
   - This is simpler for FFI than iterating struct-by-struct.

5. **Implement `bridge_free_json()`**
   ```cpp
   BRIDGE_API void bridge_free_json(const char* json);
   ```
   - Free any dynamically allocated JSON strings to prevent memory leaks.

6. **Update `native/bridge.h`** with all new declarations and struct definitions.

## Design Decisions

- Provide both a struct-based API (for efficiency) and a JSON-based API (for simplicity).
- The subagent implementing the Dart FFI layer (plan 12) can choose which to use.
- JSON approach is recommended for MVP since it avoids complex struct marshalling in Dart.

## Acceptance Criteria

- `bridge_get_profile_count()` returns the correct number of profiles.
- `bridge_get_all_profiles_json()` returns valid JSON listing all profiles.
- Profile names are correctly converted from wide strings to UTF-8.
- Predefined vs user-created flag is accurate.
- No memory leaks from JSON strings (freed via `bridge_free_json`).
