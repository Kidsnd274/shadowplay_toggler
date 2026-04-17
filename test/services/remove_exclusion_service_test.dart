import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadowplay_toggler/services/remove_exclusion_service.dart';

import '_fakes.dart';

void main() {
  setUpAll(registerCommonFallbackValues);

  group('RemoveExclusionService._deleteLocalRow (F-14)', () {
    late MockNvapiService nvapi;
    late MockManagedRulesRepository repo;
    late RemoveExclusionService service;

    setUp(() {
      nvapi = MockNvapiService();
      repo = MockManagedRulesRepository();
      service = RemoveExclusionService(nvapi, repo);

      when(() => repo.deleteRule(any())).thenAnswer((_) async {});
      when(() => repo.deleteRuleByExePath(any())).thenAnswer((_) async {});
    });

    test('prefers deleteRule(id) when the rule has an id', () async {
      final rule = fakeManagedRule(id: 42, exePath: r'C:\Games\with_id.exe');
      when(() => nvapi.clearExclusion(rule.exePath))
          .thenAnswer((_) async => {'success': true, 'action': 'deleted'});

      final result = await service.removeExclusion(rule);

      expect(result.success, isTrue);
      expect(result.removedFromLocalDb, isTrue);
      verify(() => repo.deleteRule(42)).called(1);
      verifyNever(() => repo.deleteRuleByExePath(any()));
    });

    test(
      'falls back to deleteRuleByExePath when id is null '
      '(prevents ghost rows from adopt/scan-sourced rules)',
      () async {
        final rule = fakeManagedRule(exePath: r'C:\Games\no_id.exe');
        expect(rule.id, isNull,
            reason: 'Sanity: the fake must actually be id-less for this test.');
        when(() => nvapi.clearExclusion(rule.exePath))
            .thenAnswer((_) async => {'success': true, 'action': 'deleted'});

        final result = await service.removeExclusion(rule);

        expect(result.success, isTrue);
        expect(result.removedFromLocalDb, isTrue);
        verifyNever(() => repo.deleteRule(any()));
        verify(() => repo.deleteRuleByExePath(rule.exePath)).called(1);
      },
    );

    test(
      'action == "not_found" always cleans up the local row, even with '
      'removeFromLocalDb: false',
      () async {
        final rule = fakeManagedRule(id: 7, exePath: r'C:\Games\stale.exe');
        when(() => nvapi.clearExclusion(rule.exePath))
            .thenAnswer((_) async => {'success': true, 'action': 'not_found'});

        final result =
            await service.removeExclusion(rule, removeFromLocalDb: false);

        expect(result.success, isTrue);
        expect(result.action, 'stale_db_cleanup');
        expect(result.removedFromLocalDb, isTrue,
            reason:
                'Stale driver state must not leave a dangling DB row behind, '
                'regardless of the removeFromLocalDb knob.');
        verify(() => repo.deleteRule(7)).called(1);
      },
    );

    test('removeFromLocalDb: false keeps the row for ordinary deletes',
        () async {
      final rule = fakeManagedRule(id: 11, exePath: r'C:\Games\restore.exe');
      when(() => nvapi.clearExclusion(rule.exePath))
          .thenAnswer((_) async => {'success': true, 'action': 'restored'});

      final result = await service.restoreDefault(rule);

      expect(result.success, isTrue);
      expect(result.action, 'setting_restored');
      expect(result.removedFromLocalDb, isFalse);
      verifyNever(() => repo.deleteRule(any()));
      verifyNever(() => repo.deleteRuleByExePath(any()));
    });

    test('native failure returns a human-friendly message and does not '
        'touch the DB', () async {
      final rule = fakeManagedRule(id: 3);
      when(() => nvapi.clearExclusion(rule.exePath)).thenAnswer((_) async => {
            'success': false,
            'error': 'bad',
            'nvapiStatus': -137, // invalid user privilege
          });

      final result = await service.removeExclusion(rule);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Administrator'));
      verifyNever(() => repo.deleteRule(any()));
      verifyNever(() => repo.deleteRuleByExePath(any()));
    });
  });
}
