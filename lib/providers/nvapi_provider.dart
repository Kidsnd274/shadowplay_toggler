import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nvapi_state.dart';

class NvapiNotifier extends StateNotifier<NvapiState> {
  NvapiNotifier() : super(const NvapiUninitialized());

  Future<void> initialize() async {
    state = const NvapiInitializing();
    // TODO: call native NVAPI bridge
    state = const NvapiReady();
  }

  void setError(String message) {
    state = NvapiError(message);
  }
}

final nvapiProvider = StateNotifierProvider<NvapiNotifier, NvapiState>(
  (ref) => NvapiNotifier(),
);
