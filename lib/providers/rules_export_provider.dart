import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/rules_export_service.dart';
import 'add_program_provider.dart';
import 'database_provider.dart';

final rulesExportServiceProvider = Provider<RulesExportService>((ref) {
  return RulesExportService(
    ref.read(managedRulesRepositoryProvider),
    ref.read(addProgramServiceProvider),
  );
});

/// True while an export or import is running, so the UI can disable
/// competing buttons and show a spinner.
final isExportingOrImportingRulesProvider = StateProvider<bool>((ref) => false);
