import 'dart:async';
import 'dart:isolate';

import '../native/bridge_ffi.dart';

/// FIFO single-slot mutex. Callers queue via [synchronized] and the
/// returned future resolves once *this* closure has finished
/// executing, guaranteeing no two closures are ever in flight at the
/// same time.
///
/// Exposed as a library-private class so [BridgeGateway] can own one
/// and nothing else in the codebase can grab a raw lock and try to
/// hand-roll parallelism.
///
/// Hand-rolled rather than pulling in `package:synchronized` to avoid
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

/// Top-level worker shipped to [Isolate.run] by [BridgeGateway]. The
/// worker rebuilds its own [BridgeFfi] against the same DLL path —
/// function pointers cannot cross isolates, so we can't just send one
/// across. The DLL's global state (notably `g_session`) is shared
/// with the parent isolate because Windows returns the same handle
/// for `LoadLibrary` on an already-loaded module.
///
/// Safe because the parent isolate holds [_BridgeLock] for the entire
/// [Isolate.run] call — no other caller can enter the DLL while this
/// worker is running.
String? _scanInIsolate(int settingId) {
  final bridge = BridgeFfi();
  return bridge.scanExclusionRules(settingId);
}

/// Top-level wrapper around [Isolate.run] so the closure we send
/// across the isolate boundary is constructed in a lexical scope that
/// has *no* `this` and no instance fields to accidentally capture.
///
/// The original implementation created the closure inline inside an
/// instance method. Even though `_scanInIsolate` is top-level and the
/// lambda only *syntactically* needs `settingId`, the Dart closure
/// allocator built the closure with a context that carried the
/// enclosing `this` pointer too. `Isolate.run` walked that context,
/// reached the bridge's `DynamicLibrary`, and threw:
///
/// ```
/// Invalid argument(s): Illegal argument in isolate message:
///   (object is a DynamicLibrary)
/// ```
///
/// Hoisting the `Isolate.run` call into this top-level helper means
/// the lambda's surrounding scope has only `settingId` in it —
/// trivially sendable — and the bridge no longer hitchhikes into the
/// message.
Future<String?> _runScanIsolateTopLevel(int settingId) {
  return Isolate.run(() => _scanInIsolate(settingId));
}

/// Thread-safety + isolation layer around the native bridge DLL.
///
/// The bridge (see `native/bridge.cpp`) stores NVAPI handles
/// (`g_session`, `g_error_buffer`, `g_backup_path_buffer`) in
/// process-wide statics. Two concurrent callers — e.g. the UI isolate
/// applying an exclusion while the scan worker isolate is mid-scan —
/// would corrupt those buffers. This gateway is the single door
/// every native call must go through; all access is serialised via
/// an internal lock.
///
/// Why a gateway and not just `NvapiService` owning the lock? Two
/// reasons:
///
///  1. **Single ownership of the FFI handle.** Prior to this split
///     any service could in principle be handed a [BridgeFfi] and
///     forget to serialise. Keeping the handle private to the
///     gateway means the only way to reach the DLL is through
///     [runExclusive], which is locked by construction.
///
///  2. **Testability.** Higher-level services (notably
///     [NvapiService]) can now be tested by handing them a fake
///     gateway that routes `runExclusive` into a stub bridge. The
///     test doesn't have to load a real DLL or fake out 20+
///     individual FFI calls.
///
/// One instance per process — the DLL's statics are global, so a
/// second gateway would not give us a second bridge, just a second
/// pointlessly-racing lock.
class BridgeGateway {
  BridgeGateway(this._bridge);

  final BridgeFfi _bridge;
  final _BridgeLock _lock = _BridgeLock();

  /// Execute [action] with exclusive access to the native bridge.
  /// The callback receives the [BridgeFfi] handle so it can make any
  /// native call; the lock guarantees no other caller is touching
  /// the DLL while [action] runs.
  ///
  /// Keep [action] synchronous-looking even though it's a
  /// `FutureOr<T>` — awaiting other I/O inside it holds the lock
  /// the entire time, which is correct for "must not interleave
  /// with any other bridge call" operations like [runScanIsolate]
  /// but wasteful for anything that doesn't touch the DLL.
  Future<T> runExclusive<T>(FutureOr<T> Function(BridgeFfi bridge) action) {
    return _lock.synchronized(() => action(_bridge));
  }

  /// Run the scan worker on a background isolate while holding the
  /// bridge lock. The lock is held for the entire isolate run so no
  /// main-isolate caller can enter the DLL concurrently with the
  /// worker's call.
  ///
  /// Separate method rather than "just call [runExclusive] yourself"
  /// because the top-level closure trick (see
  /// [_runScanIsolateTopLevel]) is easy to get wrong — the wrong
  /// scope and `Isolate.run` tries to serialise the bridge handle.
  Future<String?> runScanIsolate(int settingId) {
    return _lock.synchronized(() => _runScanIsolateTopLevel(settingId));
  }
}
