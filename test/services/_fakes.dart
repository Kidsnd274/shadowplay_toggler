import 'package:mocktail/mocktail.dart';
import 'package:shadowplay_toggler/models/managed_rule.dart';
import 'package:shadowplay_toggler/models/scan_result.dart';
import 'package:shadowplay_toggler/services/add_program_service.dart';
import 'package:shadowplay_toggler/services/app_state_repository.dart';
import 'package:shadowplay_toggler/services/managed_rules_repository.dart';
import 'package:shadowplay_toggler/services/nvapi_service.dart';
import 'package:shadowplay_toggler/services/remove_exclusion_service.dart';
import 'package:shadowplay_toggler/services/scan_service.dart';

class MockNvapiService extends Mock implements NvapiService {}

class MockScanService extends Mock implements ScanService {}

class MockManagedRulesRepository extends Mock
    implements ManagedRulesRepository {}

class MockAppStateRepository extends Mock implements AppStateRepository {}

class MockRemoveExclusionService extends Mock
    implements RemoveExclusionService {}

class MockAddProgramService extends Mock implements AddProgramService {}

ManagedRule fakeManagedRule({
  int? id,
  String exePath = r'C:\Games\foo.exe',
  String exeName = 'foo.exe',
  String profileName = 'foo.exe',
  int intendedValue = 0x10000000,
}) {
  final now = DateTime(2024, 1, 1);
  return ManagedRule(
    id: id,
    exePath: exePath,
    exeName: exeName,
    profileName: profileName,
    profileWasPredefined: false,
    profileWasCreated: true,
    intendedValue: intendedValue,
    createdAt: now,
    updatedAt: now,
  );
}

/// Registers fallback values for every custom type that is matched via
/// `any()` / `any(named: …)` in this test suite. Mocktail requires a
/// registered fallback per concrete type; calling this once per test
/// file `setUpAll` avoids the cryptic
/// `type 'Null' is not a subtype of type 'ManagedRule'` error.
void registerCommonFallbackValues() {
  registerFallbackValue(fakeManagedRule());
  registerFallbackValue(<ManagedRule>[]);
  registerFallbackValue(const ScanResult());
  registerFallbackValue(<String, String>{});
}
