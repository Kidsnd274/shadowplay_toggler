#include <windows.h>
#include <shlobj.h>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <string>
#include <vector>
#include "bridge.h"
#include "nvapi.h"

// ── Logging ────────────────────────────────────────────────────────

static void bridge_log(const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    int n = _vsnprintf_s(buf, sizeof(buf), _TRUNCATE, fmt, args);
    va_end(args);
    (void)n;
    OutputDebugStringA("[ShadowPlayBridge] ");
    OutputDebugStringA(buf);
    OutputDebugStringA("\n");

    // Also emit to stderr so logs appear in `flutter run`.
    // Keep messages operational-only; avoid secrets/PII in log args.
    std::fprintf(stderr, "[ShadowPlayBridge] %s\n", buf);
    std::fflush(stderr);
}

// ── Globals ────────────────────────────────────────────────────────

static bool g_initialized = false;
static NvDRSSessionHandle g_session = 0;
static char g_error_buffer[256] = {};
static char g_backup_path_buffer[MAX_PATH * 2] = {};

static const char* OOM_JSON = "{\"error\":\"out of memory\"}";

// ── Helpers ────────────────────────────────────────────────────────

static std::wstring utf8_to_wide(const char* utf8) {
    if (!utf8 || !*utf8) return {};
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    std::wstring wide(len, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &wide[0], len);
    if (!wide.empty() && wide.back() == L'\0') wide.pop_back();
    return wide;
}

static std::string wide_to_utf8(const wchar_t* wide) {
    if (!wide || !*wide) return {};
    int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    std::string utf8(len, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, &utf8[0], len, nullptr, nullptr);
    if (!utf8.empty() && utf8.back() == '\0') utf8.pop_back();
    return utf8;
}

static std::string nvu16_to_utf8(const NvU16* src) {
    return wide_to_utf8(reinterpret_cast<const wchar_t*>(src));
}

static void utf8_to_nvu16(const char* utf8, NvU16* dst, size_t dstLen) {
    if (dstLen == 0) return;
    std::wstring wide = utf8_to_wide(utf8);
    size_t copyLen = (wide.size() < dstLen - 1) ? wide.size() : dstLen - 1;
    memcpy(dst, wide.c_str(), copyLen * sizeof(NvU16));
    dst[copyLen] = 0;
}

static std::string escape_json_string(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
        }
    }
    return out;
}

static const char* alloc_json(const std::string& s) {
    char* buf = new (std::nothrow) char[s.size() + 1];
    if (!buf) return OOM_JSON;
    memcpy(buf, s.c_str(), s.size() + 1);
    return buf;
}

static NvDRSProfileHandle get_profile_handle_by_index(NvU32 index) {
    NvDRSProfileHandle hProfile = 0;
    NvAPI_Status status = NvAPI_DRS_EnumProfiles(g_session, index, &hProfile);
    return (status == NVAPI_OK) ? hProfile : 0;
}

// ── Plan 06: Initialize / Shutdown ─────────────────────────────────

int bridge_initialize() {
    bridge_log("bridge_initialize()");
    if (g_initialized) {
        bridge_log("  already initialized");
        return 0;
    }

    NvAPI_Status status = NvAPI_Initialize();
    bridge_log("  NvAPI_Initialize -> %d", static_cast<int>(status));
    if (status == NVAPI_OK) {
        g_initialized = true;
        return 0;
    }
    if (status == NVAPI_NVIDIA_DEVICE_NOT_FOUND ||
        status == NVAPI_NO_IMPLEMENTATION) {
        return -1;
    }
    return -2;
}

void bridge_shutdown() {
    bridge_log("bridge_shutdown()");
    if (g_initialized) {
        if (g_session) {
            NvAPI_Status s = NvAPI_DRS_DestroySession(g_session);
            bridge_log("  NvAPI_DRS_DestroySession -> %d", static_cast<int>(s));
            g_session = 0;
        }
        NvAPI_Unload();
        bridge_log("  NvAPI_Unload done");
        g_initialized = false;
    }
}

int bridge_is_initialized() {
    return g_initialized ? 1 : 0;
}

const char* bridge_get_error_message(int nvapi_status) {
    NvAPI_ShortString desc = {};
    NvAPI_Status result = NvAPI_GetErrorMessage(
        static_cast<NvAPI_Status>(nvapi_status), desc);

    if (result == NVAPI_OK) {
        strncpy_s(g_error_buffer, sizeof(g_error_buffer), desc, _TRUNCATE);
    } else {
        _snprintf_s(g_error_buffer, sizeof(g_error_buffer), _TRUNCATE,
                     "Unknown NVAPI error (code %d)", nvapi_status);
    }
    return g_error_buffer;
}

// ── Plan 07: DRS Session Management ────────────────────────────────

int bridge_create_session() {
    bridge_log("bridge_create_session()");
    if (g_session) {
        NvAPI_DRS_DestroySession(g_session);
        g_session = 0;
    }
    NvAPI_Status status = NvAPI_DRS_CreateSession(&g_session);
    bridge_log("  NvAPI_DRS_CreateSession -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_load_settings() {
    bridge_log("bridge_load_settings()");
    if (!g_session) { bridge_log("  no session"); return -1; }
    NvAPI_Status status = NvAPI_DRS_LoadSettings(g_session);
    bridge_log("  NvAPI_DRS_LoadSettings -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_save_settings() {
    bridge_log("bridge_save_settings()");
    if (!g_session) { bridge_log("  no session"); return -1; }
    NvAPI_Status status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  NvAPI_DRS_SaveSettings -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_destroy_session() {
    bridge_log("bridge_destroy_session()");
    if (!g_session) return 0;
    NvAPI_Status status = NvAPI_DRS_DestroySession(g_session);
    bridge_log("  NvAPI_DRS_DestroySession -> %d", static_cast<int>(status));
    g_session = 0;
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_open_session() {
    bridge_log("bridge_open_session()");
    int rc = bridge_create_session();
    if (rc != 0) return rc;

    rc = bridge_load_settings();
    if (rc != 0) {
        bridge_destroy_session();
        return rc;
    }
    return 0;
}

// ── Plan 08: Enumerate Profiles ────────────────────────────────────

int bridge_get_profile_count(int* outCount) {
    bridge_log("bridge_get_profile_count()");
    if (!g_session) { bridge_log("  no session"); return -1; }
    if (!outCount) return -1;

    NvU32 count = 0;
    NvAPI_Status status = NvAPI_DRS_GetNumProfiles(g_session, &count);
    bridge_log("  NvAPI_DRS_GetNumProfiles -> %d (count=%u)", static_cast<int>(status), count);
    if (status != NVAPI_OK) return static_cast<int>(status);
    *outCount = static_cast<int>(count);
    return 0;
}

const char* bridge_get_all_profiles_json() {
    bridge_log("bridge_get_all_profiles_json()");
    if (!g_session) return alloc_json("{\"error\":\"no session\"}");

    NvU32 count = 0;
    NvAPI_Status status = NvAPI_DRS_GetNumProfiles(g_session, &count);
    if (status != NVAPI_OK)
        return alloc_json("{\"error\":\"failed to get profile count\"}");

    bridge_log("  enumerating %u profiles", count);
    std::string json = "[";
    bool first = true;
    for (NvU32 i = 0; i < count; i++) {
        NvDRSProfileHandle hProfile = 0;
        status = NvAPI_DRS_EnumProfiles(g_session, i, &hProfile);
        if (status != NVAPI_OK) continue;

        NVDRS_PROFILE profileInfo = {};
        profileInfo.version = NVDRS_PROFILE_VER;
        status = NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
        if (status != NVAPI_OK) continue;

        std::string name = escape_json_string(nvu16_to_utf8(profileInfo.profileName));

        if (!first) json += ",";
        first = false;
        json += "{\"name\":\"" + name + "\""
                ",\"numApplications\":" + std::to_string(profileInfo.numOfApps) +
                ",\"numSettings\":" + std::to_string(profileInfo.numOfSettings) +
                ",\"isPredefined\":" + (profileInfo.isPredefined ? "true" : "false") +
                ",\"index\":" + std::to_string(i) + "}";
    }
    json += "]";
    return alloc_json(json);
}

void bridge_free_json(const char* json) {
    if (json && json != OOM_JSON) {
        delete[] json;
    }
}

// ── Plan 09: Enumerate Applications ────────────────────────────────

const char* bridge_get_profile_apps_json(int profileIndex) {
    bridge_log("bridge_get_profile_apps_json(%d)", profileIndex);
    if (!g_session) return alloc_json("[]");

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return alloc_json("[]");

    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_Status status = NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
    if (status != NVAPI_OK || profileInfo.numOfApps == 0)
        return alloc_json("[]");

    std::vector<NVDRS_APPLICATION> apps(profileInfo.numOfApps);
    for (auto& app : apps) {
        memset(&app, 0, sizeof(app));
        app.version = NVDRS_APPLICATION_VER;
    }

    NvU32 appCount = profileInfo.numOfApps;
    status = NvAPI_DRS_EnumApplications(g_session, hProfile, 0, &appCount, apps.data());
    bridge_log("  NvAPI_DRS_EnumApplications -> %d (count=%u)", static_cast<int>(status), appCount);
    if (status != NVAPI_OK) return alloc_json("[]");

    std::string json = "[";
    for (NvU32 i = 0; i < appCount; i++) {
        std::string appName    = escape_json_string(nvu16_to_utf8(apps[i].appName));
        std::string friendly   = escape_json_string(nvu16_to_utf8(apps[i].userFriendlyName));
        std::string launcher   = escape_json_string(nvu16_to_utf8(apps[i].launcher));

        if (i > 0) json += ",";
        json += "{\"appName\":\"" + appName + "\""
                ",\"friendlyName\":\"" + friendly + "\""
                ",\"launcher\":\"" + launcher + "\""
                ",\"isPredefined\":" + (apps[i].isPredefined ? "true" : "false") + "}";
    }
    json += "]";
    return alloc_json(json);
}

const char* bridge_find_application(const char* appName) {
    bridge_log("bridge_find_application(\"%s\")", appName ? appName : "(null)");
    if (!g_session || !appName)
        return alloc_json("{\"found\":false}");

    NvAPI_UnicodeString wideAppName = {};
    utf8_to_nvu16(appName, wideAppName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NVDRS_APPLICATION app = {};
    app.version = NVDRS_APPLICATION_VER;

    NvAPI_Status status = NvAPI_DRS_FindApplicationByName(
        g_session, wideAppName, &hProfile, &app);
    bridge_log("  NvAPI_DRS_FindApplicationByName -> %d", static_cast<int>(status));

    if (status != NVAPI_OK)
        return alloc_json("{\"found\":false}");

    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);

    std::string aName  = escape_json_string(nvu16_to_utf8(app.appName));
    std::string pName  = escape_json_string(nvu16_to_utf8(profileInfo.profileName));

    std::string json =
        "{\"found\":true"
        ",\"appName\":\"" + aName + "\""
        ",\"profileName\":\"" + pName + "\""
        ",\"isPredefined\":" + (app.isPredefined ? "true" : "false") +
        ",\"profileIsPredefined\":" + (profileInfo.isPredefined ? "true" : "false") + "}";
    return alloc_json(json);
}

const char* bridge_get_base_profile_apps_json() {
    bridge_log("bridge_get_base_profile_apps_json()");
    if (!g_session) return alloc_json("[]");

    NvDRSProfileHandle hBase = 0;
    NvAPI_Status status = NvAPI_DRS_GetBaseProfile(g_session, &hBase);
    bridge_log("  NvAPI_DRS_GetBaseProfile -> %d", static_cast<int>(status));
    if (status != NVAPI_OK) return alloc_json("[]");

    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    status = NvAPI_DRS_GetProfileInfo(g_session, hBase, &profileInfo);
    if (status != NVAPI_OK || profileInfo.numOfApps == 0)
        return alloc_json("[]");

    std::vector<NVDRS_APPLICATION> apps(profileInfo.numOfApps);
    for (auto& app : apps) {
        memset(&app, 0, sizeof(app));
        app.version = NVDRS_APPLICATION_VER;
    }

    NvU32 appCount = profileInfo.numOfApps;
    status = NvAPI_DRS_EnumApplications(g_session, hBase, 0, &appCount, apps.data());
    if (status != NVAPI_OK) return alloc_json("[]");

    std::string json = "[";
    for (NvU32 i = 0; i < appCount; i++) {
        std::string name = escape_json_string(nvu16_to_utf8(apps[i].appName));
        if (i > 0) json += ",";
        json += "{\"appName\":\"" + name + "\""
                ",\"isPredefined\":" + (apps[i].isPredefined ? "true" : "false") + "}";
    }
    json += "]";
    return alloc_json(json);
}

// ── Plan 10: Get/Set/Delete/Restore Settings ───────────────────────

const char* bridge_get_setting(int profileIndex, unsigned int settingId) {
    bridge_log("bridge_get_setting(%d, 0x%08X)", profileIndex, settingId);
    if (!g_session) return alloc_json("{\"found\":false}");

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return alloc_json("{\"found\":false}");

    NVDRS_SETTING setting = {};
    setting.version = NVDRS_SETTING_VER;
    NvAPI_Status status = NvAPI_DRS_GetSetting(g_session, hProfile, settingId, &setting);
    bridge_log("  NvAPI_DRS_GetSetting -> %d", static_cast<int>(status));

    if (status != NVAPI_OK)
        return alloc_json("{\"found\":false}");

    char idHex[32], curHex[32], preHex[32];
    _snprintf_s(idHex,  sizeof(idHex),  _TRUNCATE, "0x%08X", settingId);
    _snprintf_s(curHex, sizeof(curHex), _TRUNCATE, "0x%08X", setting.u32CurrentValue);
    _snprintf_s(preHex, sizeof(preHex), _TRUNCATE, "0x%08X", setting.u32PredefinedValue);

    const char* locStr = "unknown";
    switch (setting.settingLocation) {
        case NVDRS_CURRENT_PROFILE_LOCATION: locStr = "current_profile"; break;
        case NVDRS_GLOBAL_PROFILE_LOCATION:  locStr = "global_profile";  break;
        case NVDRS_BASE_PROFILE_LOCATION:    locStr = "base_profile";    break;
        case NVDRS_DEFAULT_PROFILE_LOCATION: locStr = "default_profile"; break;
    }

    std::string json =
        "{\"found\":true"
        ",\"settingId\":\"" + std::string(idHex) + "\""
        ",\"currentValue\":\"" + std::string(curHex) + "\""
        ",\"predefinedValue\":\"" + std::string(preHex) + "\""
        ",\"isCurrentPredefined\":" + (setting.isCurrentPredefined ? "true" : "false") +
        ",\"settingLocation\":\"" + locStr + "\"}";
    return alloc_json(json);
}

int bridge_set_dword_setting(int profileIndex, unsigned int settingId, unsigned int value) {
    bridge_log("bridge_set_dword_setting(%d, 0x%08X, 0x%08X)", profileIndex, settingId, value);
    if (!g_session) return -1;

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return -1;

    NVDRS_SETTING setting = {};
    setting.version = NVDRS_SETTING_VER;
    setting.settingId = settingId;
    setting.settingType = NVDRS_DWORD_TYPE;
    setting.u32CurrentValue = value;

    NvAPI_Status status = NvAPI_DRS_SetSetting(g_session, hProfile, &setting);
    bridge_log("  NvAPI_DRS_SetSetting -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_delete_setting(int profileIndex, unsigned int settingId) {
    bridge_log("bridge_delete_setting(%d, 0x%08X)", profileIndex, settingId);
    if (!g_session) return -1;

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return -1;

    NvAPI_Status status = NvAPI_DRS_DeleteProfileSetting(g_session, hProfile, settingId);
    bridge_log("  NvAPI_DRS_DeleteProfileSetting -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_restore_setting_default(int profileIndex, unsigned int settingId) {
    bridge_log("bridge_restore_setting_default(%d, 0x%08X)", profileIndex, settingId);
    if (!g_session) return -1;

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return -1;

    NvAPI_Status status = NvAPI_DRS_RestoreProfileDefaultSetting(g_session, hProfile, settingId);
    bridge_log("  NvAPI_DRS_RestoreProfileDefaultSetting -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_create_profile(const char* profileName) {
    bridge_log("bridge_create_profile(\"%s\")", profileName ? profileName : "(null)");
    if (!g_session || !profileName) return -1;

    NVDRS_PROFILE profile = {};
    profile.version = NVDRS_PROFILE_VER;
    utf8_to_nvu16(profileName, profile.profileName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NvAPI_Status status = NvAPI_DRS_CreateProfile(g_session, &profile, &hProfile);
    bridge_log("  NvAPI_DRS_CreateProfile -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_add_application(int profileIndex, const char* appName) {
    bridge_log("bridge_add_application(%d, \"%s\")", profileIndex, appName ? appName : "(null)");
    if (!g_session || !appName) return -1;

    NvDRSProfileHandle hProfile = get_profile_handle_by_index(static_cast<NvU32>(profileIndex));
    if (!hProfile) return -1;

    NVDRS_APPLICATION app = {};
    app.version = NVDRS_APPLICATION_VER;
    utf8_to_nvu16(appName, app.appName, NVAPI_UNICODE_STRING_MAX);

    NvAPI_Status status = NvAPI_DRS_CreateApplication(g_session, hProfile, &app);
    bridge_log("  NvAPI_DRS_CreateApplication -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

static constexpr unsigned int SETTING_CAPTURE_EXCLUSION = 0x809D5F60;
static constexpr unsigned int VALUE_EXCLUSION_ENABLED   = 0x10000000;

const char* bridge_apply_exclusion(const char* appName) {
    bridge_log("bridge_apply_exclusion(\"%s\")", appName ? appName : "(null)");
    if (!g_session || !appName)
        return alloc_json("{\"success\":false,\"error\":\"invalid args\"}");

    std::string exeName(appName);
    size_t lastSlash = exeName.find_last_of("\\/");
    std::string exeOnly = (lastSlash != std::string::npos)
        ? exeName.substr(lastSlash + 1) : exeName;

    std::string profileNameStr = "Capture Exclusion | " + exeOnly;

    NvAPI_UnicodeString wideAppName = {};
    utf8_to_nvu16(appName, wideAppName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NVDRS_APPLICATION existingApp = {};
    existingApp.version = NVDRS_APPLICATION_VER;

    NvAPI_Status status = NvAPI_DRS_FindApplicationByName(
        g_session, wideAppName, &hProfile, &existingApp);
    bridge_log("  FindApplicationByName -> %d", static_cast<int>(status));

    bool created = false;

    if (status != NVAPI_OK) {
        NvAPI_UnicodeString wideProfileName = {};
        utf8_to_nvu16(profileNameStr.c_str(), wideProfileName, NVAPI_UNICODE_STRING_MAX);

        status = NvAPI_DRS_FindProfileByName(g_session, wideProfileName, &hProfile);
        bridge_log("  FindProfileByName -> %d", static_cast<int>(status));

        if (status == NVAPI_PROFILE_NOT_FOUND) {
            NVDRS_PROFILE profile = {};
            profile.version = NVDRS_PROFILE_VER;
            utf8_to_nvu16(profileNameStr.c_str(), profile.profileName, NVAPI_UNICODE_STRING_MAX);

            status = NvAPI_DRS_CreateProfile(g_session, &profile, &hProfile);
            bridge_log("  CreateProfile -> %d", static_cast<int>(status));
            if (status != NVAPI_OK)
                return alloc_json("{\"success\":false,\"error\":\"failed to create profile\"}");
            created = true;
        } else if (status != NVAPI_OK) {
            return alloc_json("{\"success\":false,\"error\":\"failed to find profile\"}");
        }

        NVDRS_APPLICATION app = {};
        app.version = NVDRS_APPLICATION_VER;
        utf8_to_nvu16(appName, app.appName, NVAPI_UNICODE_STRING_MAX);

        status = NvAPI_DRS_CreateApplication(g_session, hProfile, &app);
        bridge_log("  CreateApplication -> %d", static_cast<int>(status));
        if (status != NVAPI_OK && status != NVAPI_EXECUTABLE_ALREADY_IN_USE)
            return alloc_json("{\"success\":false,\"error\":\"failed to add application\"}");
    }

    NVDRS_SETTING setting = {};
    setting.version = NVDRS_SETTING_VER;
    setting.settingId = SETTING_CAPTURE_EXCLUSION;
    setting.settingType = NVDRS_DWORD_TYPE;
    setting.u32CurrentValue = VALUE_EXCLUSION_ENABLED;

    status = NvAPI_DRS_SetSetting(g_session, hProfile, &setting);
    bridge_log("  SetSetting(0x%08X) -> %d", SETTING_CAPTURE_EXCLUSION, static_cast<int>(status));
    if (status != NVAPI_OK)
        return alloc_json("{\"success\":false,\"error\":\"failed to set setting\"}");

    status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  SaveSettings -> %d", static_cast<int>(status));
    if (status != NVAPI_OK)
        return alloc_json("{\"success\":false,\"error\":\"failed to save settings\"}");

    std::string safeName = escape_json_string(profileNameStr);
    std::string json =
        "{\"success\":true"
        ",\"profileName\":\"" + safeName + "\""
        ",\"created\":" + (created ? "true" : "false") +
        ",\"settingApplied\":true}";
    return alloc_json(json);
}

// ── Plan 11: Backup / Restore ──────────────────────────────────────

int bridge_export_settings(const char* filePath) {
    bridge_log("bridge_export_settings(\"%s\")", filePath ? filePath : "(null)");
    if (!g_session || !filePath) return -1;

    NvAPI_UnicodeString wideFile = {};
    utf8_to_nvu16(filePath, wideFile, NVAPI_UNICODE_STRING_MAX);

    NvAPI_Status status = NvAPI_DRS_SaveSettingsToFile(g_session, wideFile);
    bridge_log("  NvAPI_DRS_SaveSettingsToFile -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

int bridge_import_settings(const char* filePath) {
    bridge_log("bridge_import_settings(\"%s\")", filePath ? filePath : "(null)");
    if (!g_session || !filePath) return -1;

    NvAPI_UnicodeString wideFile = {};
    utf8_to_nvu16(filePath, wideFile, NVAPI_UNICODE_STRING_MAX);

    NvAPI_Status status = NvAPI_DRS_LoadSettingsFromFile(g_session, wideFile);
    bridge_log("  NvAPI_DRS_LoadSettingsFromFile -> %d", static_cast<int>(status));
    if (status != NVAPI_OK) return static_cast<int>(status);

    status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  NvAPI_DRS_SaveSettings -> %d", static_cast<int>(status));
    return (status == NVAPI_OK) ? 0 : static_cast<int>(status);
}

const char* bridge_get_default_backup_path() {
    bridge_log("bridge_get_default_backup_path()");
    wchar_t appDataPath[MAX_PATH] = {};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appDataPath))) {
        g_backup_path_buffer[0] = '\0';
        return g_backup_path_buffer;
    }

    std::wstring dir = std::wstring(appDataPath) + L"\\ShadowPlayToggler\\backups";
    CreateDirectoryW((std::wstring(appDataPath) + L"\\ShadowPlayToggler").c_str(), nullptr);
    CreateDirectoryW(dir.c_str(), nullptr);

    SYSTEMTIME st;
    GetLocalTime(&st);

    wchar_t filename[MAX_PATH];
    _snwprintf_s(filename, _countof(filename), _TRUNCATE,
                 L"%s\\drs_backup_%04d%02d%02d_%02d%02d%02d.nvidiaProfileInspector",
                 dir.c_str(), st.wYear, st.wMonth, st.wDay,
                 st.wHour, st.wMinute, st.wSecond);

    std::string utf8 = wide_to_utf8(filename);
    strncpy_s(g_backup_path_buffer, sizeof(g_backup_path_buffer), utf8.c_str(), _TRUNCATE);
    bridge_log("  path: %s", g_backup_path_buffer);
    return g_backup_path_buffer;
}
