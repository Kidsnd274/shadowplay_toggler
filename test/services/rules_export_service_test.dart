import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shadowplay_toggler/models/add_program_result.dart';
import 'package:shadowplay_toggler/models/rules_export.dart';
import 'package:shadowplay_toggler/services/rules_export_service.dart';

import '_fakes.dart';

void main() {
  setUpAll(() {
    registerCommonFallbackValues();
  });

  group('RulesExportService.importFromFile (F-13 path normalisation)', () {
    late MockManagedRulesRepository repo;
    late MockAddProgramService addProgram;
    late RulesExportService service;
    late Directory tempDir;

    setUp(() {
      repo = MockManagedRulesRepository();
      addProgram = MockAddProgramService();
      service = RulesExportService(repo, addProgram);

      tempDir = Directory.systemTemp.createTempSync('rules_export_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Writes a minimal, schema-v1 export document to disk and returns the
    /// file path. [exePaths] are emitted verbatim so the test can exercise
    /// the denormalised form.
    String writeDoc(List<String> exePaths) {
      final file = File(p.join(tempDir.path, 'export.json'));
      file.writeAsStringSync(jsonEncode({
        'schemaVersion': RulesExportDocument.currentSchemaVersion,
        'format': RulesExportDocument.formatId,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'rules': [
          for (final path in exePaths)
            {
              'exePath': path,
              'exeName': p.basename(path.replaceAll('\\', '/')),
              'profileName': p.basename(path.replaceAll('\\', '/')),
              'profileWasPredefined': false,
              'intendedValue': '0x10000000',
            },
        ],
      }));
      return file.path;
    }

    test(
      'normalises exePath before DB lookup and commit '
      '(skipMissingFiles: false)',
      () async {
        final denormalised = r'C:\Games\\foo.exe';
        final expected = p.normalize(denormalised);
        final docPath = writeDoc([denormalised]);

        when(() => repo.getRuleByExePath(any()))
            .thenAnswer((_) async => null);
        when(() => addProgram.commit(any())).thenAnswer((_) async {
          return const AddProgramResult(
            success: true,
            exePath: '',
            exeName: 'foo.exe',
            profileName: 'foo.exe',
            profileAlreadyExisted: false,
            exclusionAlreadyApplied: false,
            needsUserConfirmation: false,
          );
        });

        final result = await service.importFromFile(
          docPath,
          skipMissingFiles: false,
        );

        expect(result.total, 1);
        expect(result.failed, 0);
        // Both repo lookup and add-program commit see the normalised path
        // — the whole point of F-13.
        verify(() => repo.getRuleByExePath(expected)).called(1);
        verify(() => addProgram.commit(expected)).called(1);
      },
    );

    test(
      'a pre-existing row at the normalised path is counted as '
      'already-managed, not re-imported',
      () async {
        final denormalised = r'C:\Games\.\bar.exe';
        final normalised = p.normalize(denormalised);
        final docPath = writeDoc([denormalised]);

        when(() => repo.getRuleByExePath(normalised))
            .thenAnswer((_) async => fakeManagedRule(
                  id: 99,
                  exePath: normalised,
                  exeName: 'bar.exe',
                ));
        when(() => addProgram.commit(any())).thenAnswer((_) async {
          return const AddProgramResult(
            success: true,
            exePath: '',
            exeName: 'bar.exe',
            profileName: 'bar.exe',
            profileAlreadyExisted: true,
            exclusionAlreadyApplied: false,
            needsUserConfirmation: false,
          );
        });

        final result = await service.importFromFile(
          docPath,
          skipMissingFiles: false,
        );

        expect(result.alreadyManaged, 1);
        expect(result.imported, 0);
      },
    );

    test('malformed JSON bubbles up as a readable FormatException '
        '(F-11)', () async {
      final file = File(p.join(tempDir.path, 'garbage.json'));
      file.writeAsStringSync('}{');

      expect(
        () => service.importFromFile(file.path),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('not a valid JSON document'),
        )),
      );
    });

    test('top-level array instead of object throws a shape error '
        '(F-11)', () async {
      final file = File(p.join(tempDir.path, 'array.json'));
      file.writeAsStringSync('[1,2,3]');

      expect(
        () => service.importFromFile(file.path),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('JSON object at the top level'),
        )),
      );
    });
  });

  group('RulesExportEntry._parseIntendedValue (F-37)', () {
    test('accepts hex strings and bare ints', () {
      final entry = RulesExportEntry.fromJson(const {
        'exePath': r'C:\Games\foo.exe',
        'exeName': 'foo.exe',
        'profileName': 'foo.exe',
        'profileWasPredefined': false,
        'intendedValue': '0x10000000',
      });
      expect(entry.intendedValue, 0x10000000);

      final entry2 = RulesExportEntry.fromJson(const {
        'exePath': r'C:\Games\foo.exe',
        'exeName': 'foo.exe',
        'profileName': 'foo.exe',
        'profileWasPredefined': false,
        'intendedValue': 42,
      });
      expect(entry2.intendedValue, 42);
    });

    test('unparsable intendedValue throws instead of silently defaulting',
        () {
      expect(
        () => RulesExportEntry.fromJson(const {
          'exePath': r'C:\Games\foo.exe',
          'exeName': 'foo.exe',
          'profileName': 'foo.exe',
          'profileWasPredefined': false,
          'intendedValue': 'banana',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
