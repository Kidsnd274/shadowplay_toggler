import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadowplay_toggler/constants/app_constants.dart';
import 'package:shadowplay_toggler/services/scan_service.dart';

import '_fakes.dart';

/// Builds the JSON document that `bridge_scan_exclusion_rules` returns,
/// so the tests can drive [ScanService] with realistic inputs without
/// going anywhere near the native bridge.
String _scanJson({
  required List<Map<String, Object?>> rules,
  Map<String, Object?>? baseProfile,
  int profilesScanned = 1,
  int settingsFound = 1,
  int durationMs = 1,
  List<String> warnings = const [],
}) {
  final doc = <String, Object?>{
    'rules': rules,
    'baseProfile': baseProfile,
    'profilesScanned': profilesScanned,
    'settingsFound': settingsFound,
    'durationMs': durationMs,
    'warnings': warnings,
  };
  return jsonEncode(doc);
}

Map<String, Object?> _scanRule({
  required String profileName,
  required String appExePath,
  required int currentValue,
  bool profileIsPredefined = false,
  bool appIsPredefined = false,
  bool isCurrentPredefined = false,
}) {
  final hex =
      '0x${currentValue.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  return <String, Object?>{
    'profileName': profileName,
    'profileIsPredefined': profileIsPredefined,
    'appExePath': appExePath,
    'appIsPredefined': appIsPredefined,
    'currentValue': hex,
    'predefinedValue': '0x00000000',
    'isCurrentPredefined': isCurrentPredefined,
    'isPredefinedValid': false,
    'settingLocation': 'current_profile',
  };
}

void main() {
  setUpAll(registerCommonFallbackValues);

  group('ScanService classification', () {
    late MockNvapiService nvapi;
    late MockManagedRulesRepository repo;
    late ScanService service;

    setUp(() {
      nvapi = MockNvapiService();
      repo = MockManagedRulesRepository();
      service = ScanService(nvapi, repo);
    });

    test(
      'managed rule whose driver entry is a bare basename under an NVIDIA '
      'predefined profile is hydrated as Excluded, not classified as orphan '
      '(F-49: Scan Profiles flips Excluded back to Disabled)',
      () async {
        final managed = fakeManagedRule(
          id: 1,
          exePath: r'L:\Apps\Moonlight\moonlight.exe',
          exeName: 'moonlight.exe',
          profileName: 'Fear The Night',
          intendedValue: AppConstants.captureDisableValue,
        );
        when(() => repo.getAllRules()).thenAnswer((_) async => [managed]);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(
            rules: [
              // NVIDIA's predefined profile carries the exe as a bare
              // basename — the driver only stores it once even though
              // the user added it via full path.
              _scanRule(
                profileName: 'Fear The Night',
                appExePath: 'moonlight.exe',
                currentValue: AppConstants.captureDisableValue,
                profileIsPredefined: true,
              ),
            ],
          ),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(
          result.managedExeLiveValues[managed.exePath],
          AppConstants.captureDisableValue,
          reason: 'Managed rule must be hydrated with the live driver '
              'value via the basename fallback so the UI shows '
              '"Excluded" instead of "Inactive".',
        );
        expect(result.orphanedManagedRules, isEmpty,
            reason: 'A bare-name driver entry that lines up with our '
                'full-path managed rule must NOT push the rule into '
                'the orphan bucket.');
        expect(result.detectedRules, isEmpty,
            reason: 'The bare-name duplicate must also stay out of '
                'the Detected tab.');
        expect(result.driftedManagedRules, isEmpty,
            reason: 'Live value matches intended value — no drift.');
      },
    );

    test(
      'basename match also reports drift when the live value diverges '
      'from intended',
      () async {
        final managed = fakeManagedRule(
          id: 2,
          exePath: r'L:\Apps\Moonlight\moonlight.exe',
          exeName: 'moonlight.exe',
          profileName: 'Fear The Night',
          intendedValue: AppConstants.captureDisableValue,
        );
        when(() => repo.getAllRules()).thenAnswer((_) async => [managed]);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(
            rules: [
              _scanRule(
                profileName: 'Fear The Night',
                appExePath: 'moonlight.exe',
                // Driver was flipped back to "enabled" behind our back.
                currentValue: AppConstants.captureEnableValue,
                profileIsPredefined: true,
              ),
            ],
          ),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(
          result.managedExeLiveValues[managed.exePath],
          AppConstants.captureEnableValue,
        );
        expect(result.driftedManagedRules, hasLength(1));
        final drifted = result.driftedManagedRules.single;
        expect(drifted.exePath, managed.exePath);
        expect(drifted.currentValue, AppConstants.captureEnableValue);
        expect(drifted.previousValue, AppConstants.captureDisableValue,
            reason: 'previousValue carries the intended value so the '
                'drift card can show "you intended X, driver has Y".');
      },
    );

    test(
      'exact-path match still works (regression guard for the common '
      'self-created-profile case)',
      () async {
        final managed = fakeManagedRule(
          id: 3,
          exePath: r'L:\Apps\Custom\myapp.exe',
          exeName: 'myapp.exe',
          profileName: 'myapp.exe',
          intendedValue: AppConstants.captureDisableValue,
        );
        when(() => repo.getAllRules()).thenAnswer((_) async => [managed]);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(
            rules: [
              _scanRule(
                profileName: 'myapp.exe',
                appExePath: r'L:\Apps\Custom\myapp.exe',
                currentValue: AppConstants.captureDisableValue,
              ),
            ],
          ),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(
          result.managedExeLiveValues[managed.exePath],
          AppConstants.captureDisableValue,
        );
        expect(result.orphanedManagedRules, isEmpty);
        expect(result.driftedManagedRules, isEmpty);
        expect(result.detectedRules, isEmpty);
      },
    );

    test(
      'when both the bare-name and the full-path entries appear under '
      'the same profile, the full-path exact match is preferred and the '
      'bare-name duplicate is silently consumed',
      () async {
        final managed = fakeManagedRule(
          id: 4,
          exePath: r'L:\Apps\Game\foo.exe',
          exeName: 'foo.exe',
          profileName: 'Foo Game',
          intendedValue: AppConstants.captureDisableValue,
        );
        when(() => repo.getAllRules()).thenAnswer((_) async => [managed]);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(
            rules: [
              _scanRule(
                profileName: 'Foo Game',
                appExePath: r'L:\Apps\Game\foo.exe',
                currentValue: AppConstants.captureDisableValue,
                profileIsPredefined: true,
              ),
              _scanRule(
                profileName: 'Foo Game',
                appExePath: 'foo.exe',
                currentValue: AppConstants.captureDisableValue,
                profileIsPredefined: true,
              ),
            ],
          ),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(result.managedExeLiveValues, hasLength(1));
        expect(
          result.managedExeLiveValues[managed.exePath],
          AppConstants.captureDisableValue,
        );
        expect(result.detectedRules, isEmpty,
            reason: 'Bare-name duplicate must not show up as a separate '
                '"external" rule.');
        expect(result.orphanedManagedRules, isEmpty);
        expect(result.driftedManagedRules, isEmpty);
      },
    );

    test(
      'a managed rule with no matching scanned exe is still classified as '
      'orphan with a null live value',
      () async {
        final managed = fakeManagedRule(
          id: 5,
          exePath: r'L:\Apps\Removed\old.exe',
          exeName: 'old.exe',
          profileName: 'old.exe',
          intendedValue: AppConstants.captureDisableValue,
        );
        when(() => repo.getAllRules()).thenAnswer((_) async => [managed]);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(rules: const []),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(result.orphanedManagedRules, hasLength(1));
        expect(result.managedExeLiveValues[managed.exePath], isNull,
            reason: 'No live entry on the driver — UI surfaces this as '
                '"live state not verified".');
      },
    );

    test(
      'a wholly-external scanned rule (no managed match by path or '
      'basename) lands in the Detected tab',
      () async {
        when(() => repo.getAllRules()).thenAnswer((_) async => const []);
        when(() => nvapi.scanExclusionRulesJsonAsync(any())).thenAnswer(
          (_) async => _scanJson(
            rules: [
              _scanRule(
                profileName: 'Other Game',
                appExePath: r'C:\Other\bar.exe',
                currentValue: AppConstants.captureDisableValue,
              ),
            ],
          ),
        );

        final result = await service.scanProfiles();

        expect(result.hasError, isFalse, reason: result.error);
        expect(result.detectedRules, hasLength(1));
        expect(result.detectedRules.single.exePath, r'C:\Other\bar.exe');
        expect(result.managedExeLiveValues, isEmpty);
      },
    );
  });

  group('ScanService error paths', () {
    late MockNvapiService nvapi;
    late MockManagedRulesRepository repo;
    late ScanService service;

    setUp(() {
      nvapi = MockNvapiService();
      repo = MockManagedRulesRepository();
      service = ScanService(nvapi, repo);
    });

    test('returns a ScanResult.error when the bridge returns null', () async {
      when(() => nvapi.scanExclusionRulesJsonAsync(any()))
          .thenAnswer((_) async => null);

      final result = await service.scanProfiles();

      expect(result.hasError, isTrue);
      expect(result.error, contains('no data'));
    });

    test(
      'returns a ScanResult.error when the bridge returns malformed JSON',
      () async {
        when(() => nvapi.scanExclusionRulesJsonAsync(any()))
            .thenAnswer((_) async => 'not json at all');

        final result = await service.scanProfiles();

        expect(result.hasError, isTrue);
        expect(result.error, contains('malformed JSON'));
      },
    );
  });
}
