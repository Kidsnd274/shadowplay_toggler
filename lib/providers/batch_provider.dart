import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/batch_service.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';
import 'remove_exclusion_provider.dart';

final batchServiceProvider = Provider<BatchService>((ref) {
  return BatchService(
    ref.read(nvapiServiceProvider),
    ref.read(removeExclusionServiceProvider),
    ref.read(managedRulesRepositoryProvider),
  );
});
