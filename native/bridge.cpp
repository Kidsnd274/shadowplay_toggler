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

// Build a success=false JSON payload that includes the raw NVAPI status so
// the Dart side can distinguish recoverable user errors (e.g. missing admin
// privilege, status -137) from generic failures. Keep the schema compatible
// with older callers that only read `success` and `error`.
// Forward declaration so build_error_json can escape the payload.
static std::string escape_json_string(const std::string& s);

// Plan F-41: always escape the error string before embedding it in
// the JSON envelope. Today all call sites pass literals so the prior
// no-escape form happened to work, but a literal containing `"` or
// `\` — or, down the road, a dynamic message built from NVAPI text or
// a path — would emit invalid JSON and crash the Dart side with a
// `FormatException` that masks the original failure entirely.
static std::string build_error_json(const char* error, int nvapiStatus) {
    std::string out = "{\"success\":false,\"error\":\"";
    out += escape_json_string(error ? error : "");
    out += "\",\"nvapiStatus\":";
    out += std::to_string(nvapiStatus);
    out += "}";
    return out;
}

// ── Helpers ────────────────────────────────────────────────────────

// Both helpers must tolerate MultiByteToWideChar/WideCharToMultiByte
// returning 0 (which is how Win32 signals "invalid input" / "no
// buffer"). Previously the code trusted the returned length
// blindly — on failure `std::wstring wide(0, 0)` creates an empty
// string and the subsequent call writes into `&wide[0]`, which is
// only safe on some STL implementations and in any case yields a
// silently-corrupted result downstream (e.g. profile names rendering
// as empty strings in the UI). Plan F-17.
static std::wstring utf8_to_wide(const char* utf8) {
    if (!utf8 || !*utf8) return {};
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    if (len <= 0) return {};
    std::wstring wide(static_cast<size_t>(len), L'\0');
    int written = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &wide[0], len);
    if (written <= 0) return {};
    if (!wide.empty() && wide.back() == L'\0') wide.pop_back();
    return wide;
}

static std::string wide_to_utf8(const wchar_t* wide) {
    if (!wide || !*wide) return {};
    int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return {};
    std::string utf8(static_cast<size_t>(len), '\0');
    int written = WideCharToMultiByte(CP_UTF8, 0, wide, -1, &utf8[0], len, nullptr, nullptr);
    if (written <= 0) return {};
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

// Plan F-42: the previous escape table only covered the subset of C0
// controls that have shortcut escapes in the JSON grammar (`\n`,
// `\r`, `\t`). Every other byte in the `0x00..0x1F` range — e.g. a
// stray `0x01` inside a mangled NVAPI string — was emitted verbatim
// and made the whole response invalid JSON (the JSON spec forbids
// unescaped control characters in string literals). Fall back to
// `\u00XX` for any other C0 byte so we always produce well-formed
// output.
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
            case '\b': out += "\\b";  break;
            case '\f': out += "\\f";  break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    _snprintf_s(buf, sizeof(buf), _TRUNCATE,
                                "\\u%04x", static_cast<unsigned char>(c));
                    out += buf;
                } else {
                    out += c;
                }
                break;
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

    // Surface a GetProfileInfo failure instead of silently returning
    // garbage for the profile fields. The old code ignored the status
    // and let `profileInfo.profileName` be uninitialised memory when
    // NVAPI said no, which made downstream Dart decisions (e.g. "is
    // this predefined?") unreliable. Plan F-18.
    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_Status infoStatus =
        NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
    bridge_log("  GetProfileInfo -> %d", static_cast<int>(infoStatus));
    if (infoStatus != NVAPI_OK)
        return alloc_json("{\"found\":false}");

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

    // The *intended* profile name when we have to create a fresh profile.
    // If the exe is already attached to something else, we use that something
    // else's real name instead (see below).
    std::string exeName(appName);
    size_t lastSlash = exeName.find_last_of("\\/");
    std::string exeOnly = (lastSlash != std::string::npos)
        ? exeName.substr(lastSlash + 1) : exeName;

    NvAPI_UnicodeString wideAppName = {};
    utf8_to_nvu16(appName, wideAppName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NVDRS_APPLICATION existingApp = {};
    existingApp.version = NVDRS_APPLICATION_VER;

    NvAPI_Status status = NvAPI_DRS_FindApplicationByName(
        g_session, wideAppName, &hProfile, &existingApp);
    bridge_log("  FindApplicationByName -> %d", static_cast<int>(status));

    // `created` tracks only whether *we* created the profile in this call.
    // `attached` tracks whether the exe was already attached to some profile
    // before we touched it (FindApplicationByName succeeded).
    bool created = false;
    bool alreadyAttached = (status == NVAPI_OK);

    if (!alreadyAttached) {
        NvAPI_UnicodeString wideProfileName = {};
        utf8_to_nvu16(exeOnly.c_str(), wideProfileName, NVAPI_UNICODE_STRING_MAX);

        status = NvAPI_DRS_FindProfileByName(g_session, wideProfileName, &hProfile);
        bridge_log("  FindProfileByName -> %d", static_cast<int>(status));

        if (status == NVAPI_PROFILE_NOT_FOUND) {
            NVDRS_PROFILE profile = {};
            profile.version = NVDRS_PROFILE_VER;
            utf8_to_nvu16(exeOnly.c_str(), profile.profileName, NVAPI_UNICODE_STRING_MAX);

            status = NvAPI_DRS_CreateProfile(g_session, &profile, &hProfile);
            bridge_log("  CreateProfile -> %d", static_cast<int>(status));
            if (status != NVAPI_OK)
                return alloc_json(build_error_json(
                    "failed to create profile", static_cast<int>(status)));
            created = true;
        } else if (status != NVAPI_OK) {
            return alloc_json(build_error_json(
                "failed to find profile", static_cast<int>(status)));
        }

        NVDRS_APPLICATION app = {};
        app.version = NVDRS_APPLICATION_VER;
        utf8_to_nvu16(appName, app.appName, NVAPI_UNICODE_STRING_MAX);

        status = NvAPI_DRS_CreateApplication(g_session, hProfile, &app);
        bridge_log("  CreateApplication -> %d", static_cast<int>(status));
        if (status != NVAPI_OK && status != NVAPI_EXECUTABLE_ALREADY_IN_USE)
            return alloc_json(build_error_json(
                "failed to add application", static_cast<int>(status)));
    }

    // Look up the *real* profile name and predefined flag so the Dart side
    // persists accurate metadata. The exe may have been attached to a profile
    // with a completely different name (e.g. NVIDIA's shipped "Steam Games")
    // or we may have reused an existing user profile in FindProfileByName.
    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_Status infoStatus =
        NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
    bridge_log("  GetProfileInfo -> %d", static_cast<int>(infoStatus));

    std::string realProfileName = exeOnly;
    bool profileWasPredefined = false;
    if (infoStatus == NVAPI_OK) {
        realProfileName = nvu16_to_utf8(profileInfo.profileName);
        profileWasPredefined = profileInfo.isPredefined != 0;
    }

    // Capture the setting's previous value (if any) *before* we overwrite it,
    // so the caller can persist it for restore-default semantics.
    NVDRS_SETTING previous = {};
    previous.version = NVDRS_SETTING_VER;
    bool hadPreviousValue = false;
    NvAPI_Status prevStatus = NvAPI_DRS_GetSetting(
        g_session, hProfile, SETTING_CAPTURE_EXCLUSION, &previous);
    if (prevStatus == NVAPI_OK) {
        hadPreviousValue = true;
    }

    NVDRS_SETTING setting = {};
    setting.version = NVDRS_SETTING_VER;
    setting.settingId = SETTING_CAPTURE_EXCLUSION;
    setting.settingType = NVDRS_DWORD_TYPE;
    setting.u32CurrentValue = VALUE_EXCLUSION_ENABLED;

    status = NvAPI_DRS_SetSetting(g_session, hProfile, &setting);
    bridge_log("  SetSetting(0x%08X) -> %d", SETTING_CAPTURE_EXCLUSION, static_cast<int>(status));
    if (status != NVAPI_OK)
        return alloc_json(build_error_json(
            "failed to set setting", static_cast<int>(status)));

    status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  SaveSettings -> %d", static_cast<int>(status));
    if (status != NVAPI_OK)
        return alloc_json(build_error_json(
            "failed to save settings", static_cast<int>(status)));

    std::string safeName = escape_json_string(realProfileName);
    std::string json =
        "{\"success\":true"
        ",\"profileName\":\"" + safeName + "\""
        ",\"profileWasCreated\":" + (created ? "true" : "false") +
        ",\"profileWasPredefined\":" + (profileWasPredefined ? "true" : "false") +
        ",\"alreadyAttached\":" + (alreadyAttached ? "true" : "false") +
        ",\"settingApplied\":true";

    if (hadPreviousValue) {
        char prevHex[32];
        _snprintf_s(prevHex, sizeof(prevHex), _TRUNCATE,
                    "0x%08X", previous.u32CurrentValue);
        json += ",\"previousValue\":\"";
        json += prevHex;
        json += "\"";
    } else {
        json += ",\"previousValue\":null";
    }
    json += "}";
    return alloc_json(json);
}

// ── Plan 22: Remove Exclusion ──────────────────────────────────────

const char* bridge_clear_exclusion(const char* appName) {
    bridge_log("bridge_clear_exclusion(\"%s\")", appName ? appName : "(null)");
    if (!g_session || !appName)
        return alloc_json("{\"success\":false,\"error\":\"invalid args\"}");

    NvAPI_UnicodeString wideAppName = {};
    utf8_to_nvu16(appName, wideAppName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NVDRS_APPLICATION existingApp = {};
    existingApp.version = NVDRS_APPLICATION_VER;

    NvAPI_Status status = NvAPI_DRS_FindApplicationByName(
        g_session, wideAppName, &hProfile, &existingApp);
    bridge_log("  FindApplicationByName -> %d", static_cast<int>(status));

    if (status == NVAPI_EXECUTABLE_NOT_FOUND || status == NVAPI_PROFILE_NOT_FOUND) {
        return alloc_json(
            "{\"success\":true,\"action\":\"not_found\""
            ",\"profileName\":\"\"}");
    }
    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "find failed", static_cast<int>(status)));
    }

    // Guard against a GetProfileInfo failure here too (plan F-18).
    // The profileName field feeds the success response that the Dart
    // layer uses to confirm which profile was modified — if the call
    // fails we'd echo an empty name and the UI would render "cleared
    // exclusion on <blank>" with no way to correlate back.
    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_Status infoStatus2 =
        NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
    bridge_log("  GetProfileInfo -> %d", static_cast<int>(infoStatus2));
    std::string profileName =
        (infoStatus2 == NVAPI_OK) ? nvu16_to_utf8(profileInfo.profileName) : std::string{};

    NVDRS_SETTING current = {};
    current.version = NVDRS_SETTING_VER;
    NvAPI_Status getStatus = NvAPI_DRS_GetSetting(
        g_session, hProfile, SETTING_CAPTURE_EXCLUSION, &current);
    bridge_log("  GetSetting -> %d", static_cast<int>(getStatus));

    if (getStatus == NVAPI_SETTING_NOT_FOUND) {
        // Nothing to clear.
        std::string safe = escape_json_string(profileName);
        std::string json = "{\"success\":true,\"action\":\"not_set\""
                           ",\"profileName\":\"" + safe + "\"}";
        return alloc_json(json);
    }
    if (getStatus != NVAPI_OK) {
        return alloc_json(build_error_json(
            "get setting failed", static_cast<int>(getStatus)));
    }

    const char* action = "deleted";
    if (current.isPredefinedValid) {
        // NVIDIA ships a predefined value for this setting on this profile;
        // restore that value so inherited behaviour is preserved.
        status = NvAPI_DRS_RestoreProfileDefaultSetting(
            g_session, hProfile, SETTING_CAPTURE_EXCLUSION);
        bridge_log("  RestoreProfileDefaultSetting -> %d", static_cast<int>(status));
        action = "restored";
    } else {
        status = NvAPI_DRS_DeleteProfileSetting(
            g_session, hProfile, SETTING_CAPTURE_EXCLUSION);
        bridge_log("  DeleteProfileSetting -> %d", static_cast<int>(status));
    }

    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "clear failed", static_cast<int>(status)));
    }

    status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  SaveSettings -> %d", static_cast<int>(status));
    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "save failed", static_cast<int>(status)));
    }

    std::string safe = escape_json_string(profileName);
    std::string json = "{\"success\":true,\"action\":\"";
    json += action;
    json += "\",\"profileName\":\"";
    json += safe;
    json += "\"}";
    return alloc_json(json);
}

// ── Delete Profile (destructive) ───────────────────────────────────
//
// Look up a profile by name and delete it outright. Refuses to touch
// NVIDIA-predefined profiles (NvAPI_DRS_DeleteProfile would fail with
// INVALID_USER_PRIVILEGE anyway, but we short-circuit to give the
// caller a clearer error message). Saves settings on success.

const char* bridge_delete_profile(const char* profileName) {
    bridge_log("bridge_delete_profile(\"%s\")", profileName ? profileName : "(null)");
    if (!g_session || !profileName)
        return alloc_json("{\"success\":false,\"error\":\"invalid args\"}");

    NvAPI_UnicodeString wideName = {};
    utf8_to_nvu16(profileName, wideName, NVAPI_UNICODE_STRING_MAX);

    NvDRSProfileHandle hProfile = 0;
    NvAPI_Status status = NvAPI_DRS_FindProfileByName(g_session, wideName, &hProfile);
    bridge_log("  FindProfileByName -> %d", static_cast<int>(status));

    if (status == NVAPI_PROFILE_NOT_FOUND) {
        std::string safe = escape_json_string(profileName);
        std::string json = "{\"success\":true,\"action\":\"not_found\""
                           ",\"profileName\":\"" + safe + "\"}";
        return alloc_json(json);
    }
    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "find profile failed", static_cast<int>(status)));
    }

    NVDRS_PROFILE profileInfo = {};
    profileInfo.version = NVDRS_PROFILE_VER;
    NvAPI_Status infoStatus = NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
    if (infoStatus == NVAPI_OK && profileInfo.isPredefined) {
        return alloc_json(
            "{\"success\":false,\"error\":\"cannot delete NVIDIA-predefined profile\"}");
    }

    status = NvAPI_DRS_DeleteProfile(g_session, hProfile);
    bridge_log("  NvAPI_DRS_DeleteProfile -> %d", static_cast<int>(status));
    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "delete profile failed", static_cast<int>(status)));
    }

    status = NvAPI_DRS_SaveSettings(g_session);
    bridge_log("  SaveSettings -> %d", static_cast<int>(status));
    if (status != NVAPI_OK) {
        return alloc_json(build_error_json(
            "save failed", static_cast<int>(status)));
    }

    std::string safe = escape_json_string(profileName);
    std::string json = "{\"success\":true,\"action\":\"deleted\""
                       ",\"profileName\":\"" + safe + "\"}";
    return alloc_json(json);
}

// ── Plan 23: Scan Exclusion Rules ──────────────────────────────────

// Emit a single rule tuple as JSON into `out`. Does not add commas; the
// caller is responsible for separators.
static void append_rule_json(std::string& out,
                             const std::string& profileName,
                             bool profileIsPredefined,
                             const std::string& appExePath,
                             bool appIsPredefined,
                             unsigned int currentValue,
                             unsigned int predefinedValue,
                             bool isCurrentPredefined,
                             bool isPredefinedValid,
                             NVDRS_SETTING_LOCATION location) {
    char curHex[16], preHex[16];
    _snprintf_s(curHex, sizeof(curHex), _TRUNCATE, "0x%08X", currentValue);
    _snprintf_s(preHex, sizeof(preHex), _TRUNCATE, "0x%08X", predefinedValue);

    const char* loc = "unknown";
    switch (location) {
        case NVDRS_CURRENT_PROFILE_LOCATION: loc = "current_profile"; break;
        case NVDRS_GLOBAL_PROFILE_LOCATION:  loc = "global_profile";  break;
        case NVDRS_BASE_PROFILE_LOCATION:    loc = "base_profile";    break;
        case NVDRS_DEFAULT_PROFILE_LOCATION: loc = "default_profile"; break;
    }

    out += "{\"profileName\":\"";
    out += escape_json_string(profileName);
    out += "\",\"profileIsPredefined\":";
    out += profileIsPredefined ? "true" : "false";
    out += ",\"appExePath\":\"";
    out += escape_json_string(appExePath);
    out += "\",\"appIsPredefined\":";
    out += appIsPredefined ? "true" : "false";
    out += ",\"currentValue\":\"";
    out += curHex;
    out += "\",\"predefinedValue\":\"";
    out += preHex;
    out += "\",\"isCurrentPredefined\":";
    out += isCurrentPredefined ? "true" : "false";
    out += ",\"isPredefinedValid\":";
    out += isPredefinedValid ? "true" : "false";
    out += ",\"settingLocation\":\"";
    out += loc;
    out += "\"}";
}

const char* bridge_scan_exclusion_rules(unsigned int settingId) {
    bridge_log("bridge_scan_exclusion_rules(0x%08X)", settingId);
    if (!g_session) return alloc_json("{\"error\":\"no session\"}");

    LARGE_INTEGER freq = {}, startCounter = {}, endCounter = {};
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&startCounter);

    NvU32 profileCount = 0;
    NvAPI_Status status = NvAPI_DRS_GetNumProfiles(g_session, &profileCount);
    if (status != NVAPI_OK)
        return alloc_json("{\"error\":\"failed to get profile count\"}");

    std::string rulesJson = "[";
    bool firstRule = true;
    NvU32 scannedProfiles = 0;
    NvU32 settingsFound = 0;

    // Warnings for profiles we couldn't introspect cleanly. Kept
    // separate from the fatal `error` field so the Dart side can surface
    // them as a non-blocking banner instead of aborting the whole scan.
    // Plan F-19: previously any GetSetting non-OK status was silently
    // treated the same as NVAPI_SETTING_NOT_FOUND, hiding real driver
    // errors (e.g. NVAPI_ACCESS_DENIED) behind "scan returned 0 rules".
    std::vector<std::string> warnings;

    for (NvU32 i = 0; i < profileCount; i++) {
        NvDRSProfileHandle hProfile = 0;
        status = NvAPI_DRS_EnumProfiles(g_session, i, &hProfile);
        if (status != NVAPI_OK) continue;
        scannedProfiles++;

        NVDRS_PROFILE profileInfo = {};
        profileInfo.version = NVDRS_PROFILE_VER;
        status = NvAPI_DRS_GetProfileInfo(g_session, hProfile, &profileInfo);
        if (status != NVAPI_OK) {
            warnings.push_back(
                "GetProfileInfo failed on profile #" + std::to_string(i) +
                " (status " + std::to_string(static_cast<int>(status)) + ")");
            continue;
        }

        NVDRS_SETTING setting = {};
        setting.version = NVDRS_SETTING_VER;
        status = NvAPI_DRS_GetSetting(g_session, hProfile, settingId, &setting);
        if (status == NVAPI_SETTING_NOT_FOUND) {
            // Normal path: this profile simply doesn't carry the setting.
            continue;
        }
        if (status != NVAPI_OK) {
            // Profile *should* carry the setting but the call failed —
            // surface it so we don't silently under-report.
            std::string pname = nvu16_to_utf8(profileInfo.profileName);
            warnings.push_back(
                "GetSetting failed on profile \"" + pname +
                "\" (status " + std::to_string(static_cast<int>(status)) + ")");
            continue;
        }
        settingsFound++;

        std::string profileName = nvu16_to_utf8(profileInfo.profileName);
        bool profilePredef = profileInfo.isPredefined != 0;

        if (profileInfo.numOfApps == 0) {
            // Profile carries the setting but has no attached exe — rare but
            // possible. Emit a synthetic rule with an empty exePath so the
            // caller can still surface it (e.g. a Base / Global profile).
            if (!firstRule) rulesJson += ",";
            firstRule = false;
            append_rule_json(rulesJson, profileName, profilePredef,
                             "", false,
                             setting.u32CurrentValue,
                             setting.u32PredefinedValue,
                             setting.isCurrentPredefined != 0,
                             setting.isPredefinedValid != 0,
                             setting.settingLocation);
            continue;
        }

        std::vector<NVDRS_APPLICATION> apps(profileInfo.numOfApps);
        for (auto& app : apps) {
            memset(&app, 0, sizeof(app));
            app.version = NVDRS_APPLICATION_VER;
        }

        NvU32 appCount = profileInfo.numOfApps;
        NvAPI_Status enumStatus = NvAPI_DRS_EnumApplications(
            g_session, hProfile, 0, &appCount, apps.data());
        if (enumStatus != NVAPI_OK) continue;

        for (NvU32 a = 0; a < appCount; a++) {
            std::string exePath = nvu16_to_utf8(apps[a].appName);
            bool appPredef = apps[a].isPredefined != 0;

            if (!firstRule) rulesJson += ",";
            firstRule = false;
            append_rule_json(rulesJson, profileName, profilePredef,
                             exePath, appPredef,
                             setting.u32CurrentValue,
                             setting.u32PredefinedValue,
                             setting.isCurrentPredefined != 0,
                             setting.isPredefinedValid != 0,
                             setting.settingLocation);
        }
    }

    rulesJson += "]";

    // Base profile inspection — treated as inherited behaviour.
    std::string baseJson = "null";
    {
        NvDRSProfileHandle hBase = 0;
        NvAPI_Status bStatus = NvAPI_DRS_GetBaseProfile(g_session, &hBase);
        if (bStatus == NVAPI_OK && hBase) {
            NVDRS_PROFILE baseInfo = {};
            baseInfo.version = NVDRS_PROFILE_VER;
            bStatus = NvAPI_DRS_GetProfileInfo(g_session, hBase, &baseInfo);

            NVDRS_SETTING baseSetting = {};
            baseSetting.version = NVDRS_SETTING_VER;
            NvAPI_Status sStatus = NvAPI_DRS_GetSetting(
                g_session, hBase, settingId, &baseSetting);

            if (bStatus == NVAPI_OK && sStatus == NVAPI_OK) {
                std::string baseName = (baseInfo.profileName[0] == 0)
                    ? "Base Profile"
                    : nvu16_to_utf8(baseInfo.profileName);
                std::string tmp;
                append_rule_json(tmp, baseName, baseInfo.isPredefined != 0,
                                 "", false,
                                 baseSetting.u32CurrentValue,
                                 baseSetting.u32PredefinedValue,
                                 baseSetting.isCurrentPredefined != 0,
                                 baseSetting.isPredefinedValid != 0,
                                 baseSetting.settingLocation);
                baseJson = tmp;
            }
        }
    }

    QueryPerformanceCounter(&endCounter);
    double durationMs = 0.0;
    if (freq.QuadPart > 0) {
        durationMs = (endCounter.QuadPart - startCounter.QuadPart) * 1000.0
                     / static_cast<double>(freq.QuadPart);
    }
    int durationMsInt = static_cast<int>(durationMs + 0.5);
    bridge_log("  scan complete: %u profiles, %u settings, %d ms",
               scannedProfiles, settingsFound, durationMsInt);
    if (durationMsInt > 2000) {
        bridge_log("  WARNING: scan exceeded 2000 ms");
    }

    // Non-fatal warnings accumulated by the scan loop (plan F-19). The
    // Dart side surfaces these via `ScanResult.warnings` without
    // marking the whole scan as failed.
    std::string warningsJson = "[";
    for (size_t w = 0; w < warnings.size(); ++w) {
        if (w > 0) warningsJson += ",";
        warningsJson += "\"" + escape_json_string(warnings[w]) + "\"";
    }
    warningsJson += "]";

    std::string json = "{\"durationMs\":";
    json += std::to_string(durationMsInt);
    json += ",\"profilesScanned\":";
    json += std::to_string(scannedProfiles);
    json += ",\"settingsFound\":";
    json += std::to_string(settingsFound);
    json += ",\"rules\":";
    json += rulesJson;
    json += ",\"baseProfile\":";
    json += baseJson;
    json += ",\"warnings\":";
    json += warningsJson;
    json += "}";
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
