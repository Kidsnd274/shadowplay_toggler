import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nvapi_state.dart';
import '../native/bridge_ffi.dart';

class NvapiNotifier extends StateNotifier<NvapiState> {
  final BridgeFfi _bridge;

  NvapiNotifier(this._bridge) : super(const NvapiUninitialized());

  Future<void> initialize() async {
    state = const NvapiInitializing();
    try {
      final result = _bridge.initialize();
      if (result == 0) {
        state = const NvapiReady();
      } else if (result == -1) {
        state = const NvapiError('No NVIDIA GPU or driver found');
      } else {
        state = NvapiError('NVAPI init failed (code $result)');
      }
    } catch (e) {
      state = NvapiError('Bridge error: $e');
    }
  }

  void shutdown() {
    _bridge.shutdown();
    state = const NvapiUninitialized();
  }

  @override
  void dispose() {
    _bridge.shutdown();
    super.dispose();
  }
}

final bridgeFfiProvider = Provider<BridgeFfi>((ref) => BridgeFfi());

final nvapiProvider = StateNotifierProvider<NvapiNotifier, NvapiState>(
  (ref) => NvapiNotifier(ref.read(bridgeFfiProvider)),
);
