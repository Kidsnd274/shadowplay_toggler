import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import '../models/app_exception.dart';
import '../models/profile_info.dart';
import '../native/bridge_ffi.dart';

/// Thrown by [NvapiService] when the native bridge reports a non-zero
/// status or returns a failure payload.
///
/// Extends [NvapiException] so both newer UI code that catches the typed
/// [AppException] hierarchy and older code that explicitly catches
/// `NvapiBridgeException` keep working.
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
    final buf = StringBuffer('NvapiBridgeException: $message');
    if (statusCode != null) {
      buf.write(' (code $statusCode)');
    }
    if (cause != null) {
      buf.write('\n  caused by: $cause');
    }
    return buf.toString();
  }
}

/// FIFO single-slot mutex. Callers queue via [synchronized] and the
/// returned future resolves once *this* closure has finished executing,
/// guaranteeing no two closures are ever in flight at the same time.
///
/// Kept private to [NvapiService] so nothing outside this file can forget
/// to go through the lock: every bridge call the rest of the app makes is
/// funnelled through a method that acquires it.
///
/// We hand-roll this rather than pull in `package:synchronized` to avoid
/// growing `pubspec.yaml` for a 20-line primitive.
class _BridgeLock {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(FutureOr<T> Function() action) async {
    final prev = _tail;
    final next = Completer<void>();
    _tail = next.future;
    try {
      await prev;
      return await action();
    } finally {
      next.complete();
    }
  }
}

/// Top-level worker shipped to [Isolate.run] by
/// [_runScanIsolate]. Function pointers cannot cross isolates, so we
/// reconstruct a [BridgeFfi] in the worker against the same DLL
/// path. The DLL's global state (notably `g_session`) is shared with
/// the parent isolate because Windows returns the same handle for
/// `LoadLibrary` on an already-loaded module.
///
/// Safe because the parent isolate holds [_bridgeLock] for the entire
/// [Isolate.run] call — no other `NvapiService` method can enter the DLL
/// while this worker is running.
String? _scanInIsolate(int settingId) {
  final bridge = BridgeFfi();
  return bridge.scanExclusionRules(settingId);
}

/// Top-level wrapper around [Isolate.run] so the closure we send across
/// the isolate boundary is constructed in a lexical scope that has *no*
/// `this` and no instance fields to accidentally capture.
///
/// The original implementation created the closure inline inside
/// [NvapiService.scanExclusionRulesJsonAsync]:
///
/// ```dart
/// return await Isolate.run(() => _scanInIsolate(settingId));
/// ```
///
/// Even though `_scanInIsolate` is top-level and the lambda only
/// *syntactically* needs `settingId`, the Dart closure allocator built
/// the closure with a context that carried the enclosing `this`
/// pointer too (`Context num_variables: 2`). `Isolate.run` walked that
/// context, reached `_bridge`, reached its `DynamicLibrary`, and threw:
///
/// ```
/// Invalid argument(s): Illegal argument in isolate message:
///   (object is a DynamicLibrary)
/// ```
///
/// Hoisting the `Isolate.run` call into this top-level helper means
/// the lambda's surrounding scope has only `settingId` in it — trivially
/// sendable — and the bridge no longer hitchhikes into the message.
Future<String?> _runScanIsolate(int settingId) {
  return Isolate.run(() => _scanInIsolate(settingId));
}

/// Single shared lock for the bridge DLL's global state.
///
/// Rationale (see the code-review doc, finding F-01/F-15): the native
/// bridge stores NVAPI handles (`g_session`, `g_error_buffer`,
/// `g_backup_path_buffer`) in process-wide statics. Two concurrent
/// callers — e.g. the UI isolate applying an exclusion while the scan
/// worker isolate is mid-scan — would corrupt those buffers. A Dart-side
/// mutex serialising every [NvapiService] entry point is the minimum
/// correct fix.
///
/// Top-level so it is shared across every [NvapiService] instance the
/// provider ever hands out. Effectively a singleton, keyed by the DLL
/// rather than any particular Dart object.
final _BridgeLock _bridgeLock = _BridgeLock();

/// Thin Dart wrapper around [BridgeFfi] that serialises every native
/// call through [_bridgeLock]. Every public method is `async` and must
/// be `await`ed — calling one without awaiting will still queue it
/// correctly but you lose the ability to see its result / exception.
class NvapiService {
  final BridgeFfi _bridge;

  NvapiService(this._bridge);

  void _checkStatus(int result, String operation) {
    if (result != 0) {
      final msg = _bridge.getErrorMessage(result);
      throw NvapiBridgeException(
        '$operation failed: $msg',
        statusCode: result,
      );
    }
  }

  /// Raises a clean [NvapiBridgeException] if the native bridge has not
  /// been initialised yet. Without this guard the native calls would
  /// still fail, but via a lower-level error path (the bridge returns
  /// `no session`-style JSON or NVAPI's generic status, which the UI
  /// then surfaces as a confusing "Failed to get profiles" rather than
  /// the actual root cause). Plan F-20.
  ///
  /// Called from inside each locked section so no caller can race
  /// initialise-shutdown with a real NVAPI call.
  void _requireInitialized(String operation) {
    if (_bridge.isInitialized() == 0) {
      throw NvapiBridgeException(
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
      throw NvapiBridgeException(
        '$operation returned malformed JSON: ${e.message}',
        cause: e,
        stackTrace: st,
      );
    }
    try {
      return parser(decoded);
    } on TypeError catch (e, st) {
      throw NvapiBridgeException(
        '$operation returned JSON with unexpected shape: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ── Session helpers ─────────────────────────────────────────────

  Future<void> openSession() => _bridgeLock.synchronized(() {
        _requireInitialized('Open session');
        _checkStatus(_bridge.openSession(), 'Open session');
      });

  Future<void> createSession() => _bridgeLock.synchronized(() {
        _requireInitialized('Create session');
        _checkStatus(_bridge.createSession(), 'Create session');
      });

  Future<void> loadSettings() => _bridgeLock.synchronized(() {
        _requireInitialized('Load settings');
        _checkStatus(_bridge.loadSettings(), 'Load settings');
      });

  Future<void> saveSettings() => _bridgeLock.synchronized(() {
        _requireInitialized('Save settings');
        _checkStatus(_bridge.saveSettings(), 'Save settings');
      });

  Future<void> destroySession() => _bridgeLock.synchronized(() {
        _requireInitialized('Destroy session');
        _checkStatus(_bridge.destroySession(), 'Destroy session');
      });

  // ── Profiles ────────────────────────────────────────────────────

  Future<int> getProfileCount() => _bridgeLock.synchronized(() {
        _requireInitialized('Get profile count');
        final count = _bridge.getProfileCount();
        if (count < 0) {
          throw const NvapiBridgeException('Failed to get profile count');
        }
        return count;
      });

  Future<List<ProfileInfo>> getAllProfiles() => _bridgeLock.synchronized(() {
        _requireInitialized('Get all profiles');
        final json = _bridge.getAllProfilesJson();
        if (json == null) {
          throw const NvapiBridgeException('Failed to get profiles JSON');
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
      _bridgeLock.synchronized(() {
        _requireInitialized('Get profile apps');
        final json = _bridge.getProfileAppsJson(profileIndex);
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
      _bridgeLock.synchronized(() {
        _requireInitialized('Find application');
        return _parseJson(
          _bridge.findApplication(exePath),
          'Find application',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<List<Map<String, dynamic>>> getBaseProfileApps() =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Get base-profile apps');
        final json = _bridge.getBaseProfileAppsJson();
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
      _bridgeLock.synchronized(() {
        _requireInitialized('Get setting');
        return _parseJson(
          _bridge.getSetting(profileIndex, settingId),
          'Get setting',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<void> setDwordSetting(int profileIndex, int settingId, int value) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Set DWORD setting');
        _checkStatus(
          _bridge.setDwordSetting(profileIndex, settingId, value),
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
      _bridgeLock.synchronized(() {
        _requireInitialized('Set DWORD setting');
        return _bridge.setDwordSetting(profileIndex, settingId, value);
      });

  Future<void> deleteSetting(int profileIndex, int settingId) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Delete setting');
        _checkStatus(
          _bridge.deleteSetting(profileIndex, settingId),
          'Delete setting',
        );
      });

  /// Non-throwing variant of [deleteSetting].
  Future<int> deleteSettingRaw(int profileIndex, int settingId) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Delete setting');
        return _bridge.deleteSetting(profileIndex, settingId);
      });

  Future<void> restoreSettingDefault(int profileIndex, int settingId) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Restore setting default');
        _checkStatus(
          _bridge.restoreSettingDefault(profileIndex, settingId),
          'Restore setting default',
        );
      });

  /// Non-throwing variant of [restoreSettingDefault]. A non-zero return
  /// typically means the setting has no NVIDIA-predefined default on this
  /// profile, in which case the caller should fall back to
  /// [deleteSettingRaw].
  Future<int> restoreSettingDefaultRaw(int profileIndex, int settingId) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Restore setting default');
        return _bridge.restoreSettingDefault(profileIndex, settingId);
      });

  Future<void> createProfile(String name) => _bridgeLock.synchronized(() {
        _requireInitialized('Create profile');
        _checkStatus(_bridge.createProfile(name), 'Create profile "$name"');
      });

  Future<void> addApplication(int profileIndex, String exePath) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Add application');
        _checkStatus(
          _bridge.addApplication(profileIndex, exePath),
          'Add application',
        );
      });

  Future<Map<String, dynamic>?> applyExclusion(String exePath) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Apply exclusion');
        return _parseJson(
          _bridge.applyExclusion(exePath),
          'Apply exclusion',
          (d) => d as Map<String, dynamic>,
        );
      });

  Future<Map<String, dynamic>?> clearExclusion(String exePath) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Clear exclusion');
        return _parseJson(
          _bridge.clearExclusion(exePath),
          'Clear exclusion',
          (d) => d as Map<String, dynamic>,
        );
      });

  /// Delete the whole DRS profile identified by [profileName]. Refuses to
  /// operate on NVIDIA-predefined profiles (native layer enforces this).
  /// Returns the raw response JSON as a map; see `bridge_delete_profile`.
  Future<Map<String, dynamic>?> deleteProfile(String profileName) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Delete profile');
        return _parseJson(
          _bridge.deleteProfile(profileName),
          'Delete profile',
          (d) => d as Map<String, dynamic>,
        );
      });

  // ── Scan ────────────────────────────────────────────────────────

  /// Runs the native scan on a worker isolate and returns the raw JSON
  /// document. The bridge lock is held for the entire isolate run so no
  /// main-isolate `NvapiService` call can enter the DLL concurrently with
  /// the worker's call.
  ///
  /// Callers still need to decode / post-process the JSON themselves —
  /// that's a pure-Dart operation kept out of the lock.
  Future<String?> scanExclusionRulesJsonAsync(int settingId) =>
      _bridgeLock.synchronized(() async {
        _requireInitialized('Scan exclusion rules');
        // Hop out of the instance method so the closure handed to
        // `Isolate.run` doesn't pick up `this` — see `_runScanIsolate`
        // for the long version.
        return await _runScanIsolate(settingId);
      });

  // ── Backup / Restore ───────────────────────────────────────────

  Future<void> exportSettings(String filePath) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Export settings');
        _checkStatus(_bridge.exportSettings(filePath), 'Export settings');
      });

  Future<void> importSettings(String filePath) =>
      _bridgeLock.synchronized(() {
        _requireInitialized('Import settings');
        _checkStatus(_bridge.importSettings(filePath), 'Import settings');
      });

  /// Returns the DLL's opinion of the default backup path. This doesn't
  /// touch NVAPI (only Win32 path helpers) but we keep it under the lock
  /// too because the DLL writes into its `g_backup_path_buffer` static.
  Future<String> getDefaultBackupPath() => _bridgeLock.synchronized(() {
        return _bridge.getDefaultBackupPath();
      });
}
