import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── Native C signatures ─────────────────────────────────────────

typedef _VoidVoidC = Void Function();
typedef _IntVoidC = Int32 Function();
typedef _PtrIntC = Pointer<Utf8> Function(Int32 status);
typedef _PtrVoidC = Pointer<Utf8> Function();
typedef _FreeJsonC = Void Function(Pointer<Utf8> json);
typedef _GetProfileCountC = Int32 Function(Pointer<Int32> outCount);
typedef _PtrProfileIndexC = Pointer<Utf8> Function(Int32 profileIndex);
typedef _PtrStrC = Pointer<Utf8> Function(Pointer<Utf8> name);
typedef _GetSettingC = Pointer<Utf8> Function(
    Int32 profileIndex, Uint32 settingId);
typedef _SetDwordC = Int32 Function(
    Int32 profileIndex, Uint32 settingId, Uint32 value);
typedef _SettingOpC = Int32 Function(Int32 profileIndex, Uint32 settingId);
typedef _StrReturnsIntC = Int32 Function(Pointer<Utf8> str);
typedef _AddAppC = Int32 Function(Int32 profileIndex, Pointer<Utf8> appName);
typedef _ScanRulesC = Pointer<Utf8> Function(Uint32 settingId);

/// Plan F-51: matches the C `BridgeLogCallback` typedef in `bridge.h`.
/// `NativeCallable.listener` produces a function pointer with this
/// shape and hands it to `bridge_set_log_callback`.
typedef _BridgeLogCallbackC = Void Function(Pointer<Utf8> message);
typedef _SetLogCallbackC = Void Function(
    Pointer<NativeFunction<_BridgeLogCallbackC>> cb);

// ── Dart signatures ─────────────────────────────────────────────

typedef _VoidVoidDart = void Function();
typedef _IntVoidDart = int Function();
typedef _PtrIntDart = Pointer<Utf8> Function(int status);
typedef _PtrVoidDart = Pointer<Utf8> Function();
typedef _FreeJsonDart = void Function(Pointer<Utf8> json);
typedef _GetProfileCountDart = int Function(Pointer<Int32> outCount);
typedef _PtrProfileIndexDart = Pointer<Utf8> Function(int profileIndex);
typedef _PtrStrDart = Pointer<Utf8> Function(Pointer<Utf8> name);
typedef _GetSettingDart = Pointer<Utf8> Function(
    int profileIndex, int settingId);
typedef _SetDwordDart = int Function(
    int profileIndex, int settingId, int value);
typedef _SettingOpDart = int Function(int profileIndex, int settingId);
typedef _StrReturnsIntDart = int Function(Pointer<Utf8> str);
typedef _AddAppDart = int Function(int profileIndex, Pointer<Utf8> appName);
typedef _ScanRulesDart = Pointer<Utf8> Function(int settingId);
typedef _SetLogCallbackDart = void Function(
    Pointer<NativeFunction<_BridgeLogCallbackC>> cb);

class BridgeFfi {
  late final DynamicLibrary _lib;

  // Log bridging (plan F-51)
  late final _SetLogCallbackDart _setLogCallback;

  /// Retained so the GC doesn't collect the native-callable trampoline
  /// while the DLL still holds a pointer to it. Non-null only on the
  /// isolate that called [setLogCallback] — the scan worker isolate
  /// uses its own [BridgeFfi] and never registers a listener.
  NativeCallable<_BridgeLogCallbackC>? _logCallable;

  // Lifecycle
  late final int Function() initialize;
  late final void Function() shutdown;
  late final int Function() isInitialized;
  late final _PtrIntDart _getErrorMessage;

  // Session
  late final int Function() createSession;
  late final int Function() loadSettings;
  late final int Function() saveSettings;
  late final int Function() destroySession;
  late final int Function() openSession;

  // Profiles
  late final _GetProfileCountDart _getProfileCount;
  late final _PtrVoidDart _getAllProfilesJson;
  late final _FreeJsonDart _freeJson;

  // Applications
  late final _PtrProfileIndexDart _getProfileAppsJson;
  late final _PtrStrDart _findApplication;
  late final _PtrVoidDart _getBaseProfileAppsJson;

  // Settings
  late final _GetSettingDart _getSetting;
  late final _SetDwordDart _setDwordSetting;
  late final _SettingOpDart _deleteSetting;
  late final _SettingOpDart _restoreSettingDefault;
  late final _StrReturnsIntDart _createProfile;
  late final _AddAppDart _addApplication;
  late final _PtrStrDart _applyExclusion;
  late final _PtrStrDart _clearExclusion;
  late final _PtrStrDart _deleteProfile;
  late final _ScanRulesDart _scanExclusionRules;

  // Backup
  late final _StrReturnsIntDart _exportSettings;
  late final _StrReturnsIntDart _importSettings;
  late final _PtrVoidDart _getDefaultBackupPath;

  BridgeFfi() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _lib = DynamicLibrary.open('$exeDir/shadowplay_bridge.dll');

    _bindAll();
  }

  void _bindAll() {
    // Log bridging (plan F-51). Resolved first so setLogCallback is
    // usable the moment the BridgeFfi ctor returns — we want the Dart
    // listener wired up *before* any other native call runs, otherwise
    // bridge_initialize()'s own log lines are lost.
    _setLogCallback =
        _lib.lookupFunction<_SetLogCallbackC, _SetLogCallbackDart>(
            'bridge_set_log_callback');

    // Lifecycle
    initialize =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_initialize');
    shutdown =
        _lib.lookupFunction<_VoidVoidC, _VoidVoidDart>('bridge_shutdown');
    isInitialized =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_is_initialized');
    _getErrorMessage =
        _lib.lookupFunction<_PtrIntC, _PtrIntDart>('bridge_get_error_message');

    // Session
    createSession =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_create_session');
    loadSettings =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_load_settings');
    saveSettings =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_save_settings');
    destroySession =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_destroy_session');
    openSession =
        _lib.lookupFunction<_IntVoidC, _IntVoidDart>('bridge_open_session');

    // Profiles
    _getProfileCount =
        _lib.lookupFunction<_GetProfileCountC, _GetProfileCountDart>(
            'bridge_get_profile_count');
    _getAllProfilesJson = _lib
        .lookupFunction<_PtrVoidC, _PtrVoidDart>('bridge_get_all_profiles_json');
    _freeJson =
        _lib.lookupFunction<_FreeJsonC, _FreeJsonDart>('bridge_free_json');

    // Applications
    _getProfileAppsJson =
        _lib.lookupFunction<_PtrProfileIndexC, _PtrProfileIndexDart>(
            'bridge_get_profile_apps_json');
    _findApplication =
        _lib.lookupFunction<_PtrStrC, _PtrStrDart>('bridge_find_application');
    _getBaseProfileAppsJson = _lib.lookupFunction<_PtrVoidC, _PtrVoidDart>(
        'bridge_get_base_profile_apps_json');

    // Settings
    _getSetting = _lib
        .lookupFunction<_GetSettingC, _GetSettingDart>('bridge_get_setting');
    _setDwordSetting = _lib
        .lookupFunction<_SetDwordC, _SetDwordDart>('bridge_set_dword_setting');
    _deleteSetting = _lib
        .lookupFunction<_SettingOpC, _SettingOpDart>('bridge_delete_setting');
    _restoreSettingDefault =
        _lib.lookupFunction<_SettingOpC, _SettingOpDart>(
            'bridge_restore_setting_default');
    _createProfile = _lib
        .lookupFunction<_StrReturnsIntC, _StrReturnsIntDart>(
            'bridge_create_profile');
    _addApplication =
        _lib.lookupFunction<_AddAppC, _AddAppDart>('bridge_add_application');
    _applyExclusion =
        _lib.lookupFunction<_PtrStrC, _PtrStrDart>('bridge_apply_exclusion');
    _clearExclusion =
        _lib.lookupFunction<_PtrStrC, _PtrStrDart>('bridge_clear_exclusion');
    _deleteProfile =
        _lib.lookupFunction<_PtrStrC, _PtrStrDart>('bridge_delete_profile');
    _scanExclusionRules =
        _lib.lookupFunction<_ScanRulesC, _ScanRulesDart>(
            'bridge_scan_exclusion_rules');

    // Backup
    _exportSettings = _lib
        .lookupFunction<_StrReturnsIntC, _StrReturnsIntDart>(
            'bridge_export_settings');
    _importSettings = _lib
        .lookupFunction<_StrReturnsIntC, _StrReturnsIntDart>(
            'bridge_import_settings');
    _getDefaultBackupPath = _lib.lookupFunction<_PtrVoidC, _PtrVoidDart>(
        'bridge_get_default_backup_path');
  }

  // ── Dart-friendly wrappers ──────────────────────────────────────

  String getErrorMessage(int status) {
    final ptr = _getErrorMessage(status);
    if (ptr == nullptr) return 'Unknown error (code $status)';
    return ptr.toDartString();
  }

  int getProfileCount() {
    final outCount = calloc<Int32>();
    try {
      final result = _getProfileCount(outCount);
      if (result != 0) return -1;
      return outCount.value;
    } finally {
      calloc.free(outCount);
    }
  }

  String? getAllProfilesJson() => _readJson(_getAllProfilesJson());

  String? getProfileAppsJson(int profileIndex) =>
      _readJson(_getProfileAppsJson(profileIndex));

  String? findApplication(String appName) {
    final namePtr = appName.toNativeUtf8();
    try {
      return _readJson(_findApplication(namePtr));
    } finally {
      malloc.free(namePtr);
    }
  }

  String? getBaseProfileAppsJson() => _readJson(_getBaseProfileAppsJson());

  String? getSetting(int profileIndex, int settingId) =>
      _readJson(_getSetting(profileIndex, settingId));

  int setDwordSetting(int profileIndex, int settingId, int value) {
    return _setDwordSetting(profileIndex, settingId, value);
  }

  int deleteSetting(int profileIndex, int settingId) {
    return _deleteSetting(profileIndex, settingId);
  }

  int restoreSettingDefault(int profileIndex, int settingId) {
    return _restoreSettingDefault(profileIndex, settingId);
  }

  int createProfile(String profileName) {
    final namePtr = profileName.toNativeUtf8();
    try {
      return _createProfile(namePtr);
    } finally {
      malloc.free(namePtr);
    }
  }

  int addApplication(int profileIndex, String appName) {
    final namePtr = appName.toNativeUtf8();
    try {
      return _addApplication(profileIndex, namePtr);
    } finally {
      malloc.free(namePtr);
    }
  }

  String? applyExclusion(String appName) {
    final namePtr = appName.toNativeUtf8();
    try {
      return _readJson(_applyExclusion(namePtr));
    } finally {
      malloc.free(namePtr);
    }
  }

  String? clearExclusion(String appName) {
    final namePtr = appName.toNativeUtf8();
    try {
      return _readJson(_clearExclusion(namePtr));
    } finally {
      malloc.free(namePtr);
    }
  }

  String? deleteProfile(String profileName) {
    final namePtr = profileName.toNativeUtf8();
    try {
      return _readJson(_deleteProfile(namePtr));
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Full DRS walk collecting every profile that carries [settingId].
  /// Returns the raw JSON document produced by the native side; see
  /// `plans/23-scan-profiles-feature.md` for the shape.
  String? scanExclusionRules(int settingId) =>
      _readJson(_scanExclusionRules(settingId));

  int exportSettings(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    try {
      return _exportSettings(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  int importSettings(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    try {
      return _importSettings(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Returns a pointer to an internal static buffer — do not free.
  String getDefaultBackupPath() {
    final ptr = _getDefaultBackupPath();
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  // ── Log bridging (plan F-51) ────────────────────────────────────

  /// Wire every `bridge_log(…)` line from the native DLL into [callback].
  /// Call this once, on the main isolate, before any other bridge call
  /// — register it after [BridgeFfi] is constructed but before
  /// `bridge_initialize()` runs, otherwise the init-time log lines
  /// from the DLL are discarded.
  ///
  /// The callback runs asynchronously on this isolate's event loop
  /// (via [NativeCallable.listener]), which is exactly what makes it
  /// safe for NVAPI worker threads *and* the scan worker isolate to
  /// call back in — both share the DLL and therefore the same global
  /// `g_log_callback` pointer.
  ///
  /// Re-registering replaces (and closes) the previous listener. The
  /// native side takes ownership of the heap-allocated message; we
  /// free it via [_freeJson] once Dart has copied it to a String, so
  /// the DLL's [alloc_json] output matches [bridge_free_json]'s
  /// deallocator.
  void setLogCallback(void Function(String message) callback) {
    _logCallable?.close();
    final callable = NativeCallable<_BridgeLogCallbackC>.listener(
      (Pointer<Utf8> msg) {
        if (msg == nullptr) return;
        try {
          callback(msg.toDartString());
        } catch (_) {
          // Never let a Dart-side logging bug take down the app.
          // Swallow and still free the native buffer below.
        } finally {
          _freeJson(msg);
        }
      },
    );
    _logCallable = callable;
    _setLogCallback(callable.nativeFunction);
  }

  /// Stops forwarding native log lines into Dart. Safe to call even if
  /// no callback was registered; harmless to call repeatedly.
  void clearLogCallback() {
    _setLogCallback(
      Pointer<NativeFunction<_BridgeLogCallbackC>>.fromAddress(0),
    );
    _logCallable?.close();
    _logCallable = null;
  }

  // ── Internal helpers ────────────────────────────────────────────

  /// Copies a heap-allocated JSON string to Dart and frees the native pointer.
  String? _readJson(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeJson(ptr);
    }
  }
}
