import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/remove_exclusion_service.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

final removeExclusionServiceProvider = Provider<RemoveExclusionService>((ref) {
  return RemoveExclusionService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
  );
});
