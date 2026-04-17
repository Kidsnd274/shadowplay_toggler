import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/add_program_service.dart';
import 'apply_exclusion_provider.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

final addProgramServiceProvider = Provider<AddProgramService>((ref) {
  return AddProgramService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
    ref.read(applyExclusionServiceProvider),
  );
});
