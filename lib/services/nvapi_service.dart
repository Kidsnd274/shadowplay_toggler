import 'dart:convert';

import '../models/app_exception.dart';
import '../models/profile_info.dart';
import '../native/bridge_ffi.dart';
import 'bridge_gateway.dart';

/// Thrown by [NvapiService] when anything goes wrong on the native-bridge
/// side. This is now the base class for two more specific failure modes:
///
///  * [NvapiNativeException] — the DLL itself said no (non-zero NVAPI
///    status, uninitialised session, etc.). `statusCode` carries the
///    raw NVAPI code when available.
///  * [NvapiProtocolException] — the DLL returned *something*, but
///    Dart couldn't make sense of it (malformed JSON, wrong shape,
///    unexpected type). The root `FormatException` / `TypeError` is
///    attached via [AppException.cause].
///
/// Retained as a concrete class so existing `catch` clauses across the
/// codebase (`on NvapiBridgeException catch (e) {}`) keep matching.
/// Greenfield code should prefer catching the typed subclass to
/// differentiate error UX (e.g. "retry the scan" for a protocol glitch
/// vs. "check the driver" for a native failure).
class NvapiBridgeException extends NvapiException {
  const NvapiBridgeException(
    super.message, {
    super.statusCode,
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buf = StringBuffer('$runtimeType: $message');
    if (statusCode != null) {
      buf.write(' (code $statusCode)');
    }
    if (cause != null) {
      buf.write('\n  caused by: $cause');
    }
    return buf.toString();
  }
}

/// The native DLL returned an error: non-zero `NvAPI_Status`, a
/// `{success:false,...}` payload, or a guard like
/// `_requireInitialized` firing before any call could be made.
///
/// `statusCode`, when present, is the raw NVAPI status value from the
/// bridge — not something we should try to show the user directly but
/// useful in logs and bug reports.
class NvapiNativeException extends NvapiBridgeException {
  const NvapiNativeException(
    super.message, {
    super.statusCode,
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });
}

/// The native DLL returned a payload that Dart couldn't parse or that
/// didn't match the expected shape. Usually indicates a bridge/Dart
/// version skew or a corrupt response — the operation itself may or may
/// not have succeeded on the driver side.
class NvapiProtocolException extends NvapiBridgeException {
  const NvapiProtocolException(
    super.message, {
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });
}

/// Typed, high-level wrapper around the native bridge. Each public
/// method routes through [BridgeGateway] so the DLL's global statics
/// (see [BridgeGateway]) can't be raced by two callers. Every method
/// is `async` and must be `await`ed — an un-awaited call still queues
/// correctly but drops the result/exception on the floor.
class NvapiService {
  NvapiService(this._gateway);

  final BridgeGateway _gateway;

  void _checkStatus(BridgeFfi bridge, int result, String operation) {
    if (result != 0) {
      final msg = bridge.getErrorMessage(result);
      throw NvapiNativeException(
        '$operation failed: $msg',
        statusCode: result,
      );
    }
  }

  /// Raises a clean [NvapiNativeException] if the native bridge has
  /// not been initialised yet. Without this guard the native calls
  /// would still fail, but via a lower-level error path (the bridge
  /// returns `no session`-style JSON or NVAPI's generic status, which
  /// the UI then surfaces as a confusing "Failed to get profiles"
  /// rather than the actual root cause). Plan F-20.
  ///
  /// Called from inside each gateway-locked section so no caller can
  /// race initialise-shutdown with a real NVAPI call.
  void _requireInitialized(BridgeFfi bridge, String operation) {
    if (bridge.isInitialized() == 0) {
      throw NvapiNativeException(
        '$operation requires an initialised NVAPI bridge — call '
        'NvapiNotifier.initialize() before entering this flow.',
      );
    }
  }

  /// Decodes [json] and routes it through [parser], translating every
  /// failure mode — malformed JSON, wrong top-level type, parser
  /// throwing because a field is missing — into a uniform
  /// [NvapiBridgeException]. Without this, callers would see the raw
  /// `FormatException` / `TypeError` out of `dart:convert`, which leaks
  /// the bridge's protocol into the UI and is miserable to debug
  /// because neither exception mentions which native call produced the
  /// bad payload (plan F-11).
  ///
  /// Returns `null` only when [json] itself is null (an absent
  /// response, which several bridge endpoints legitimately return).
  T? _parseJson<T>(
    String? json,
    String operation,
    T Function(dynamic) parser,
  ) {
    if (json == null) return null;
    return _parseJsonNonNull<T>(json, operation, parser);
  }

  /// Non-null variant of [_parseJson] for bridge endpoints whose JSON
  /// has already been null-checked inline (i.e. the caller wants to
  /// raise a specific "no payload" error before reaching the parser).
  T _parseJsonNonNull<T>(
    String json,
    String operation,
    T Function(dynamic) parser,
  ) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e, st) {
      // Plan F-38: carry the original `FormatException` (with its
      // offset and source snippet) plus the stack trace so the Logs
      // screen and any crash reporter can pinpoint *where* in the
      // bridge output the decoder gave up.
      throw NvapiProtocolException(
        '$operation returned malformed JSON: ${e.message}',
        cause: e,
        stackTrace: st,
      );
    }
    try {
      return parser(decoded);
    } on TypeError catch (e, st) {
      throw NvapiProtocolException(
        '$operation returned JSON with unexpected shape: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ── Session helpers ─────────────────────────────────────────────

  Future<void> openSession() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Open session');
        _checkStatus(bridge, bridge.openSession(), 'Open session');
      });

  Future<void> createSession() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Create session');
        _checkStatus(bridge, bridge.createSession(), 'Create session');
      });

  Future<void> loadSettings() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Load settings');
        _checkStatus(bridge, bridge.loadSettings(), 'Load settings');
      });

  Future<void> saveSettings() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Save settings');
        _checkStatus(bridge, bridge.saveSettings(), 'Save settings');
      });

  Future<void> destroySession() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Destroy session');
        _checkStatus(bridge, bridge.destroySession(), 'Destroy session');
      });

  // ── Profiles ────────────────────────────────────────────────────

  Future<int> getProfileCount() => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Get profile count');
        final count = bridge.getProfileCount();
        if (count < 0) {
          throw const NvapiNativeException('Failed to get profile count');
        }
        return count;
      });

  Future<List<ProfileInfo>> getAllProfiles() =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Get all profiles');
        final json = bridge.getAllProfilesJson();
        if (json == null) {
          throw const NvapiNativeException('Failed to get profiles JSON');
        }
        return _parseJsonNonNull<List<ProfileInfo>>(
          json,
          'Get all profiles',
          (d) => (d as List<dynamic>)
              .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      });

  // ── Applications ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProfileApps(int profileIndex) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Get profile apps');
        final json = bridge.getProfileAppsJson(profileIndex);
        if (json == null) return <Map<String, dynamic>>[];
        return _parseJsonNonNull<List<Map<String, dynamic>>>(
          json,
          'Get profile apps',
          (d) => (d as List<dynamic>)
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        );
      });

  Future<Map<String, dynamic>?> findApplication(String exePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Find application');
        return _parseJson(
          bridge.findApplication(exePath),
          'Find application',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<List<Map<String, dynamic>>> getBaseProfileApps() =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Get base-profile apps');
        final json = bridge.getBaseProfileAppsJson();
        if (json == null) return <Map<String, dynamic>>[];
        return _parseJsonNonNull<List<Map<String, dynamic>>>(
          json,
          'Get base-profile apps',
          (d) => (d as List<dynamic>)
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        );
      });

  // ── Settings ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getSetting(int profileIndex, int settingId) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Get setting');
        return _parseJson(
          bridge.getSetting(profileIndex, settingId),
          'Get setting',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<void> setDwordSetting(int profileIndex, int settingId, int value) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Set DWORD setting');
        _checkStatus(
          bridge,
          bridge.setDwordSetting(profileIndex, settingId, value),
          'Set DWORD setting',
        );
      });

  /// Non-throwing variant of [setDwordSetting]. Returns the native status
  /// code (0 on success). Use when the caller wants to branch on specific
  /// NVAPI error codes without an exception in the common path.
  Future<int> setDwordSettingRaw(
    int profileIndex,
    int settingId,
    int value,
  ) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Set DWORD setting');
        return bridge.setDwordSetting(profileIndex, settingId, value);
      });

  Future<void> deleteSetting(int profileIndex, int settingId) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Delete setting');
        _checkStatus(
          bridge,
          bridge.deleteSetting(profileIndex, settingId),
          'Delete setting',
        );
      });

  /// Non-throwing variant of [deleteSetting].
  Future<int> deleteSettingRaw(int profileIndex, int settingId) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Delete setting');
        return bridge.deleteSetting(profileIndex, settingId);
      });

  Future<void> restoreSettingDefault(int profileIndex, int settingId) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Restore setting default');
        _checkStatus(
          bridge,
          bridge.restoreSettingDefault(profileIndex, settingId),
          'Restore setting default',
        );
      });

  /// Non-throwing variant of [restoreSettingDefault]. A non-zero return
  /// typically means the setting has no NVIDIA-predefined default on this
  /// profile, in which case the caller should fall back to
  /// [deleteSettingRaw].
  Future<int> restoreSettingDefaultRaw(int profileIndex, int settingId) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Restore setting default');
        return bridge.restoreSettingDefault(profileIndex, settingId);
      });

  Future<void> createProfile(String name) => _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Create profile');
        _checkStatus(
            bridge, bridge.createProfile(name), 'Create profile "$name"');
      });

  Future<void> addApplication(int profileIndex, String exePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Add application');
        _checkStatus(
          bridge,
          bridge.addApplication(profileIndex, exePath),
          'Add application',
        );
      });

  Future<Map<String, dynamic>?> applyExclusion(String exePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Apply exclusion');
        return _parseJson(
          bridge.applyExclusion(exePath),
          'Apply exclusion',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<Map<String, dynamic>?> clearExclusion(String exePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Clear exclusion');
        return _parseJson(
          bridge.clearExclusion(exePath),
          'Clear exclusion',
          (d) => d as Map<String, dynamic>,
        );
      });

  /// Delete the whole DRS profile identified by [profileName]. Refuses to
  /// operate on NVIDIA-predefined profiles (native layer enforces this).
  /// Returns the raw response JSON as a map; see `bridge_delete_profile`.
  Future<Map<String, dynamic>?> deleteProfile(String profileName) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Delete profile');
        return _parseJson(
          bridge.deleteProfile(profileName),
          'Delete profile',
          (d) => d as Map<String, dynamic>,
        );
      });

  // ── Scan ────────────────────────────────────────────────────────

  /// Runs the native scan on a worker isolate and returns the raw JSON
  /// document. The bridge lock is held for the entire isolate run so no
  /// main-isolate `NvapiService` call can enter the DLL concurrently with
  /// the worker's call — see [BridgeGateway.runScanIsolate].
  ///
  /// Callers still need to decode / post-process the JSON themselves —
  /// that's a pure-Dart operation kept out of the lock.
  Future<String?> scanExclusionRulesJsonAsync(int settingId) {
    // We don't need a pre-flight `_requireInitialized` here: the
    // scan isolate rebuilds its own BridgeFfi and the DLL's own
    // `bridge_is_initialized` check runs inside that worker. If the
    // DLL really isn't initialised, the scan returns a
    // `{success:false,error:"..."}` payload that the caller unwraps
    // exactly like any other NVAPI failure.
    return _gateway.runScanIsolate(settingId);
  }

  // ── Backup / Restore ───────────────────────────────────────────

  Future<void> exportSettings(String filePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Export settings');
        _checkStatus(
            bridge, bridge.exportSettings(filePath), 'Export settings');
      });

  Future<void> importSettings(String filePath) =>
      _gateway.runExclusive((bridge) {
        _requireInitialized(bridge, 'Import settings');
        _checkStatus(
            bridge, bridge.importSettings(filePath), 'Import settings');
      });

  /// Returns the DLL's opinion of the default backup path. This doesn't
  /// touch NVAPI (only Win32 path helpers) but we keep it under the lock
  /// too because the DLL writes into its `g_backup_path_buffer` static.
  Future<String> getDefaultBackupPath() => _gateway.runExclusive((bridge) {
        return bridge.getDefaultBackupPath();
      });
}
