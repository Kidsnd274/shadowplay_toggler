import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/apply_exclusion_service.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

/// Shared primitive for "apply the exclusion + persist the managed
/// row". Depended on by the Add-Program, Adopt, and Enable flows.
final applyExclusionServiceProvider = Provider<ApplyExclusionService>((ref) {
  return ApplyExclusionService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
  );
});
