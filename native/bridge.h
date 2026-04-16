#pragma once

#ifdef BUILDING_BRIDGE
#define BRIDGE_API __declspec(dllexport)
#else
#define BRIDGE_API __declspec(dllimport)
#endif

extern "C" {

    // ── Plan 06: Initialize / Shutdown ─────────────────────────────
    //
    // bridge_get_error_message returns a pointer to an internal static
    // buffer. Do NOT pass it to bridge_free_json.

    BRIDGE_API int  bridge_initialize();
    BRIDGE_API void bridge_shutdown();
    BRIDGE_API int  bridge_is_initialized();
    BRIDGE_API const char* bridge_get_error_message(int nvapi_status);

    // ── Plan 07: DRS Session Management ────────────────────────────

    BRIDGE_API int bridge_create_session();
    BRIDGE_API int bridge_load_settings();
    BRIDGE_API int bridge_save_settings();
    BRIDGE_API int bridge_destroy_session();
    BRIDGE_API int bridge_open_session();

    // ── Plan 08: Enumerate Profiles ────────────────────────────────
    //
    // All functions returning const char* JSON below allocate on the
    // heap. The caller MUST pass the pointer to bridge_free_json when
    // done.

    BRIDGE_API int  bridge_get_profile_count(int* outCount);
    BRIDGE_API const char* bridge_get_all_profiles_json();
    BRIDGE_API void bridge_free_json(const char* json);

    // ── Plan 09: Enumerate Applications ────────────────────────────

    BRIDGE_API const char* bridge_get_profile_apps_json(int profileIndex);
    BRIDGE_API const char* bridge_find_application(const char* appName);
    BRIDGE_API const char* bridge_get_base_profile_apps_json();

    // ── Plan 10: Get/Set/Delete/Restore Settings ───────────────────

    BRIDGE_API const char* bridge_get_setting(int profileIndex, unsigned int settingId);
    BRIDGE_API int bridge_set_dword_setting(int profileIndex, unsigned int settingId, unsigned int value);
    BRIDGE_API int bridge_delete_setting(int profileIndex, unsigned int settingId);
    BRIDGE_API int bridge_restore_setting_default(int profileIndex, unsigned int settingId);
    BRIDGE_API int bridge_create_profile(const char* profileName);
    BRIDGE_API int bridge_add_application(int profileIndex, const char* appName);
    BRIDGE_API const char* bridge_apply_exclusion(const char* appName);

    // ── Plan 22: Remove Exclusion ──────────────────────────────────
    //
    // Clears the capture-exclusion setting override on whatever profile
    // the exe is currently attached to. Uses RestoreProfileDefaultSetting
    // when the setting has a NVIDIA-predefined default for this profile,
    // DeleteProfileSetting otherwise. NEVER deletes the profile or
    // detaches the application. Saves settings on success.

    BRIDGE_API const char* bridge_clear_exclusion(const char* appName);

    // ── Plan 23: Scan Exclusion Rules ──────────────────────────────
    //
    // Single-crossing full DRS walk. Enumerates every profile, queries
    // the requested setting, collects the attached applications for the
    // profiles that carry the setting, and returns the whole thing as a
    // single JSON document. Also reports the Base Profile's setting
    // state separately so callers can surface inherited behaviour.

    BRIDGE_API const char* bridge_scan_exclusion_rules(unsigned int settingId);

    // ── Plan 11: Backup / Restore ──────────────────────────────────
    //
    // bridge_get_default_backup_path returns a pointer to an internal
    // static buffer. Do NOT pass it to bridge_free_json.

    BRIDGE_API int bridge_export_settings(const char* filePath);
    BRIDGE_API int bridge_import_settings(const char* filePath);
    BRIDGE_API const char* bridge_get_default_backup_path();
}
