import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadowplay_toggler/models/remove_result.dart';
import 'package:shadowplay_toggler/services/batch_service.dart';

import '_fakes.dart';

void main() {
  setUpAll(registerCommonFallbackValues);

  group('BatchService.batchEnable (F-10 partial-failure plumbing)', () {
    late MockNvapiService nvapi;
    late MockRemoveExclusionService remove;
    late MockManagedRulesRepository repo;
    late BatchService service;

    setUp(() {
      nvapi = MockNvapiService();
      remove = MockRemoveExclusionService();
      repo = MockManagedRulesRepository();
      service = BatchService(nvapi, remove, repo);

      when(() => repo.updateRule(any())).thenAnswer((_) async {});
      when(() => repo.insertRule(any())).thenAnswer((_) async => 1);
    });

    test('populates errorsByExePath only for failing rows', () async {
      final ok = fakeManagedRule(
        id: 1,
        exePath: r'C:\Games\ok.exe',
        exeName: 'ok.exe',
      );
      final bad = fakeManagedRule(
        id: 2,
        exePath: r'C:\Games\bad.exe',
        exeName: 'bad.exe',
      );

      when(() => nvapi.applyExclusion(ok.exePath))
          .thenAnswer((_) async => {'success': true});
      when(() => nvapi.applyExclusion(bad.exePath))
          .thenAnswer((_) async => {
                'success': false,
                'error': 'nope',
              });

      final result = await service.batchEnable([ok, bad]);

      expect(result.total, 2);
      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(result.hasFailures, isTrue);

      // Failed row surfaces in both the human list AND the machine-
      // friendly map — the latter is what drives the UI's optimistic-
      // update gate (see BatchActionBar + didFailFor).
      expect(result.errors.single, 'bad.exe: nope');
      expect(result.errorsByExePath, {bad.exePath: 'nope'});
      expect(result.didFailFor(bad.exePath), isTrue);
      expect(result.didFailFor(ok.exePath), isFalse,
          reason: 'Successful rows must never land in errorsByExePath.');
    });

    test('thrown NvapiException is recorded by exePath', () async {
      final bad = fakeManagedRule(exePath: r'C:\Games\throws.exe');
      when(() => nvapi.applyExclusion(bad.exePath))
          .thenThrow(const FormatException('boom'));

      final result = await service.batchEnable([bad]);

      expect(result.failed, 1);
      expect(result.errorsByExePath, isNotEmpty);
      expect(result.errorsByExePath.keys.single, bad.exePath);
    });

    test('empty input returns an all-zero result without touching NVAPI',
        () async {
      final result = await service.batchEnable([]);

      expect(result.total, 0);
      expect(result.succeeded, 0);
      expect(result.failed, 0);
      expect(result.errorsByExePath, isEmpty);
      verifyNever(() => nvapi.applyExclusion(any()));
    });
  });

  group('BatchService.batchDisable (F-10 partial-failure plumbing)', () {
    late MockNvapiService nvapi;
    late MockRemoveExclusionService remove;
    late MockManagedRulesRepository repo;
    late BatchService service;

    setUp(() {
      nvapi = MockNvapiService();
      remove = MockRemoveExclusionService();
      repo = MockManagedRulesRepository();
      service = BatchService(nvapi, remove, repo);
    });

    test('populates errorsByExePath only for failing rows', () async {
      final ok = fakeManagedRule(
        id: 1,
        exePath: r'C:\Games\ok.exe',
        exeName: 'ok.exe',
      );
      final bad = fakeManagedRule(
        id: 2,
        exePath: r'C:\Games\bad.exe',
        exeName: 'bad.exe',
      );

      when(() => remove.restoreDefault(ok)).thenAnswer((_) async =>
          const RemoveResult(
              success: true,
              action: 'setting_restored',
              removedFromLocalDb: false));
      when(() => remove.restoreDefault(bad)).thenAnswer((_) async =>
          RemoveResult.failure('cannot restore'));

      final result = await service.batchDisable([ok, bad]);

      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(result.errorsByExePath, {bad.exePath: 'cannot restore'});
      expect(result.didFailFor(bad.exePath), isTrue);
    });
  });
}
