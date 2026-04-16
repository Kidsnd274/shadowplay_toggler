import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/nvapi_service.dart';
import 'nvapi_provider.dart';

final nvapiServiceProvider = Provider<NvapiService>((ref) {
  final bridge = ref.read(bridgeFfiProvider);
  return NvapiService(bridge);
});
