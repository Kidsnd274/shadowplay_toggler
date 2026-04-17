import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadowplay_toggler/models/managed_rule.dart';
import 'package:shadowplay_toggler/models/scan_result.dart';
import 'package:shadowplay_toggler/services/reconciliation_service.dart';

import '_fakes.dart';

void main() {
  setUpAll(registerCommonFallbackValues);

  group('ReconciliationService', () {
    late MockScanService scan;
    late MockManagedRulesRepository rulesRepo;
    late MockAppStateRepository stateRepo;
    late ReconciliationService service;

    setUp(() {
      scan = MockScanService();
      rulesRepo = MockManagedRulesRepository();
      stateRepo = MockAppStateRepository();
      service = ReconciliationService(scan, rulesRepo, stateRepo);

      when(() => stateRepo.getValue(any())).thenAnswer((_) async => null);
      when(() => stateRepo.setValues(any())).thenAnswer((_) async {});
    });

    test(
        'takes a single managed-rules snapshot and feeds it to the scan '
        '(F-06)', () async {
      final snapshot = [
        fakeManagedRule(id: 1, exePath: r'C:\Games\foo.exe', exeName: 'foo.exe'),
        fakeManagedRule(id: 2, exePath: r'C:\Games\bar.exe', exeName: 'bar.exe'),
      ];
      when(() => rulesRepo.getAllRules())
          .thenAnswer((_) async => List<ManagedRule>.of(snapshot));
      when(() => scan.scanProfiles(
            managedSnapshot: any(named: 'managedSnapshot'),
          )).thenAnswer((_) async => const ScanResult());

      final result = await service.reconcile();

      expect(result.hasFatalError, isFalse,
          reason: result.fatalError ?? 'no error');
      verify(() => rulesRepo.getAllRules()).called(1);
      final captured = verify(() => scan.scanProfiles(
            managedSnapshot: captureAny(named: 'managedSnapshot'),
          )).captured.single as List<ManagedRule>?;
      expect(captured, isNotNull);
      expect(captured, equals(snapshot),
          reason: 'Scan must see the exact same snapshot the reconciler '
              'used for classification.');
    });

    test('repo mutation mid-reconciliation does not leak into the scan '
        'snapshot (F-06)', () async {
      final snapshot = [
        fakeManagedRule(id: 1, exePath: r'C:\Games\foo.exe', exeName: 'foo.exe'),
      ];

      // Second call to getAllRules would return an entirely different list
      // — the scan must never see it.
      var calls = 0;
      when(() => rulesRepo.getAllRules()).thenAnswer((_) async {
        calls++;
        if (calls == 1) return List<ManagedRule>.of(snapshot);
        return <ManagedRule>[];
      });
      when(() => scan.scanProfiles(
            managedSnapshot: any(named: 'managedSnapshot'),
          )).thenAnswer((_) async => const ScanResult());

      await service.reconcile();

      verify(() => rulesRepo.getAllRules()).called(1);
    });

    test('persists drs hash and timestamp in a single transaction '
        '(F-22)', () async {
      when(() => rulesRepo.getAllRules()).thenAnswer((_) async => const []);
      when(() => scan.scanProfiles(
            managedSnapshot: any(named: 'managedSnapshot'),
          )).thenAnswer((_) async => const ScanResult());

      await service.reconcile();

      final captured =
          verify(() => stateRepo.setValues(captureAny())).captured.single
              as Map<String, String>;
      expect(captured.keys,
          containsAll([
            ReconciliationKeys.drsProfileHash,
            ReconciliationKeys.lastReconcileAt,
          ]));
      // Nothing else should be smuggled into the reconcile transaction.
      expect(captured.length, 2);
      verifyNever(() => stateRepo.setValue(any(), any()));
    });

    test('surfaces a fatal error when reading managed rules throws',
        () async {
      when(() => rulesRepo.getAllRules()).thenThrow(StateError('db closed'));

      final result = await service.reconcile();

      expect(result.hasFatalError, isTrue);
      expect(result.fatalError, contains('Failed to load managed rules'));
      verifyNever(() => scan.scanProfiles(
            managedSnapshot: any(named: 'managedSnapshot'),
          ));
    });

    test('surfaces a fatal error when the scan throws', () async {
      when(() => rulesRepo.getAllRules()).thenAnswer((_) async => const []);
      when(() => scan.scanProfiles(
            managedSnapshot: any(named: 'managedSnapshot'),
          )).thenThrow(StateError('bridge gone'));

      final result = await service.reconcile();

      expect(result.hasFatalError, isTrue);
      expect(result.fatalError, contains('Reconciliation scan failed'));
    });
  });
}
