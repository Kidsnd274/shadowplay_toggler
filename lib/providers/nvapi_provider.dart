import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nvapi_state.dart';
import '../native/bridge_ffi.dart';

class NvapiNotifier extends StateNotifier<NvapiState> {
  final BridgeFfi _bridge;

  NvapiNotifier(this._bridge) : super(const NvapiUninitialized());

  /// Initialize NVAPI and open a DRS session.
  ///
  /// The session is created + `LoadSettings` populated for the lifetime of
  /// the process; downstream features (add program, scan, backup, remove)
  /// all assume a session is already live.
  Future<void> initialize() async {
    state = const NvapiInitializing();
    try {
      final initResult = _bridge.initialize();
      if (initResult == -1) {
        state = const NvapiError('No NVIDIA GPU or driver found');
        return;
      }
      if (initResult != 0) {
        state = NvapiError('NVAPI init failed (code $initResult)');
        return;
      }

      final sessionResult = _bridge.openSession();
      if (sessionResult != 0) {
        final msg = _bridge.getErrorMessage(sessionResult);
        state = NvapiError(
          'Failed to open DRS session: $msg (code $sessionResult)',
        );
        return;
      }

      state = const NvapiReady();
    } catch (e) {
      state = NvapiError('Bridge error: $e');
    }
  }

  void shutdown() {
    try {
      _bridge.destroySession();
    } catch (_) {
      // Non-fatal; the DLL will clean up on shutdown anyway.
    }
    _bridge.shutdown();
    state = const NvapiUninitialized();
  }

  @override
  void dispose() {
    try {
      _bridge.destroySession();
    } catch (_) {}
    _bridge.shutdown();
    super.dispose();
  }
}

final bridgeFfiProvider = Provider<BridgeFfi>((ref) => BridgeFfi());

final nvapiProvider = StateNotifierProvider<NvapiNotifier, NvapiState>(
  (ref) => NvapiNotifier(ref.read(bridgeFfiProvider)),
);
