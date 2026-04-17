import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/bridge_gateway.dart';
import '../services/nvapi_service.dart';
import 'nvapi_provider.dart';

/// The single [BridgeGateway] for the process. Kept as its own
/// provider so anything lower-level than [NvapiService] (e.g. future
/// instrumentation, a diagnostic panel) can reach the gateway without
/// going through the typed service wrapper.
final bridgeGatewayProvider = Provider<BridgeGateway>((ref) {
  return BridgeGateway(ref.read(bridgeFfiProvider));
});

final nvapiServiceProvider = Provider<NvapiService>((ref) {
  return NvapiService(ref.read(bridgeGatewayProvider));
});
