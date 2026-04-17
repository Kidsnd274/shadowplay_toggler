import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/adopt_rule_service.dart';
import 'apply_exclusion_provider.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

/// Stateless [AdoptRuleService] — one instance per container.
final adoptRuleServiceProvider = Provider<AdoptRuleService>((ref) {
  return AdoptRuleService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
    ref.read(applyExclusionServiceProvider),
  );
});
