# 12 - Dart FFI Bindings

## Goal

Create the Dart FFI layer that connects the Flutter app to the native `shadowplay_bridge.dll`.

## Prerequisites

- Plan 05 (Native Bridge CMake Setup) completed.
- Plan 06-11 (Bridge functions) completed (or at least the function signatures in `bridge.h` are defined).

## Background

Flutter uses `dart:ffi` to call native C functions. The bridge DLL exports simple C functions that return integers or JSON strings. The Dart side needs to:
1. Load the DLL
2. Look up each function symbol
3. Provide Dart-friendly wrappers that handle marshalling

## Tasks

1. **Add `ffi` dependency to `pubspec.yaml`**
   - `dart:ffi` is part of the SDK, no extra package needed.
   - Optionally add `package:ffi` for convenience helpers (e.g., `calloc`, `malloc`, string conversion).
   - Add `ffi: ^2.0.0` (or latest) to dependencies.

2. **Create `lib/services/nvapi_bridge.dart`**
   - This is the main FFI binding class.
   - Load the DLL:
     ```dart
     final DynamicLibrary _lib = DynamicLibrary.open('shadowplay_bridge.dll');
     ```
   - Define typedefs for each native function and its Dart signature:
     ```dart
     // Native: int bridge_initialize()
     typedef BridgeInitializeNative = Int32 Function();
     typedef BridgeInitializeDart = int Function();
     ```

3. **Bind all functions from plans 06-11**

   Group by category:

   **Lifecycle (plan 06):**
   - `initialize()` -> `bridge_initialize`
   - `shutdown()` -> `bridge_shutdown`
   - `isInitialized()` -> `bridge_is_initialized`
   - `getErrorMessage(int status)` -> `bridge_get_error_message`

   **Session (plan 07):**
   - `createSession()` -> `bridge_create_session`
   - `loadSettings()` -> `bridge_load_settings`
   - `saveSettings()` -> `bridge_save_settings`
   - `destroySession()` -> `bridge_destroy_session`
   - `openSession()` -> `bridge_open_session`

   **Profiles (plan 08):**
   - `getProfileCount()` -> `bridge_get_profile_count`
   - `getAllProfilesJson()` -> `bridge_get_all_profiles_json`

   **Applications (plan 09):**
   - `getProfileAppsJson(int index)` -> `bridge_get_profile_apps_json`
   - `findApplication(String exePath)` -> `bridge_find_application`

   **Settings (plan 10):**
   - `getSetting(int profileIndex, int settingId)` -> `bridge_get_setting`
   - `setDwordSetting(int profileIndex, int settingId, int value)` -> `bridge_set_dword_setting`
   - `deleteSetting(int profileIndex, int settingId)` -> `bridge_delete_setting`
   - `restoreSettingDefault(int profileIndex, int settingId)` -> `bridge_restore_setting_default`
   - `applyExclusion(String exePath)` -> `bridge_apply_exclusion`
   - `createProfile(String name)` -> `bridge_create_profile`
   - `addApplication(int profileIndex, String exePath)` -> `bridge_add_application`

   **Backup (plan 11):**
   - `exportSettings(String filePath)` -> `bridge_export_settings`
   - `importSettings(String filePath)` -> `bridge_import_settings`

4. **Handle string marshalling**
   - For functions that accept `const char*`: convert Dart `String` to `Pointer<Utf8>` using `toNativeUtf8()`, call the function, then free the pointer.
   - For functions that return `const char*` (JSON): convert `Pointer<Utf8>` to Dart `String` using `.toDartString()`.
   - For JSON return values, call `bridge_free_json()` after copying the string to Dart.

5. **Create `lib/services/nvapi_service.dart`**
   - A higher-level service class that wraps `NvapiBridge` with Dart-friendly APIs.
   - Parse JSON responses into Dart model objects (`ExclusionRule`, profile info, etc.).
   - Handle errors by throwing Dart exceptions with meaningful messages.
   - Example methods:
     ```dart
     Future<List<ProfileInfo>> getAllProfiles();
     Future<ExclusionRule?> findApplication(String exePath);
     Future<void> applyExclusion(String exePath);
     Future<void> removeExclusion(String exePath);
     Future<void> exportBackup(String filePath);
     Future<void> importBackup(String filePath);
     ```

6. **Create `lib/models/profile_info.dart`**
   - Data class for profile information returned from the bridge:
     ```dart
     class ProfileInfo {
       final String name;
       final int numApplications;
       final int numSettings;
       final bool isPredefined;
       final int index;
     }
     ```

7. **Write unit tests**
   - Create `test/services/nvapi_bridge_test.dart`.
   - Test string marshalling helpers.
   - Test JSON parsing logic (mock the bridge responses).
   - Cannot test actual NVAPI calls in CI, but can test the Dart wrapping logic.

## Acceptance Criteria

- `NvapiBridge` class loads the DLL and binds all exported functions.
- `NvapiService` provides clean Dart APIs that return model objects.
- String marshalling (Dart String <-> native UTF-8) works correctly.
- JSON responses are parsed into typed Dart objects.
- Errors from the bridge are converted to Dart exceptions.
- `flutter analyze` reports no errors.
