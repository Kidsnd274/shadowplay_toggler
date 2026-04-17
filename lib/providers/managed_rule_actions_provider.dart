import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/managed_rule_actions_service.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

final managedRuleActionsServiceProvider =
    Provider<ManagedRuleActionsService>((ref) {
  return ManagedRuleActionsService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
  );
});
