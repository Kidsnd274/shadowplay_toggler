import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/rules_export.dart';
import 'add_program_service.dart';
import 'managed_rules_repository.dart';

/// Serialises the local managed-rules table to / from a portable JSON
/// document so the user can quickly re-create their exclusion list after a
/// driver reinstall wipes NVIDIA's DRS database.
///
/// Design notes:
///   * Export is local-DB-only; it does not talk to NVAPI. The intended
///     state of each rule is what we captured when the user added it.
///   * Import delegates to [AddProgramService.commit] for each entry so
///     the NVAPI write + local-DB upsert go through the exact same code
///     path as "Add Program". Entries whose `.exe` is no longer on disk
///     are skipped with a warning — re-importing later, once the game is
///     reinstalled, will pick them up.
class RulesExportService {
  final ManagedRulesRepository _repo;
  final AddProgramService _addProgram;
  final String? _appVersion;

  RulesExportService(
    this._repo,
    this._addProgram, {
    String? appVersion,
  }) : _appVersion = appVersion;

  /// Write the current managed-rules table to [filePath] as a pretty-printed
  /// JSON document. Returns the number of rules written.
  Future<int> exportToFile(String filePath) async {
    final rules = await _repo.getAllRules();
    final doc = RulesExportDocument(
      schemaVersion: RulesExportDocument.currentSchemaVersion,
      format: RulesExportDocument.formatId,
      exportedAt: DateTime.now().toUtc(),
      appVersion: _appVersion,
      rules: rules
          .map((r) => RulesExportEntry(
                exePath: r.exePath,
                exeName: r.exeName,
                profileName: r.profileName,
                profileWasPredefined: r.profileWasPredefined,
                intendedValue: r.intendedValue,
              ))
          .toList(),
    );

    final encoder = const JsonEncoder.withIndent('  ');
    final json = encoder.convert(doc.toJson());
    await File(filePath).writeAsString(json, flush: true);
    return rules.length;
  }

  /// Parse [filePath] and re-apply every rule through [AddProgramService].
  ///
  /// [skipMissingFiles] controls what happens when an entry's `.exe` is not
  /// currently on disk. When true (default), those entries are skipped and
  /// surfaced via [RulesImportResult.skippedMissingFile]. When false, they
  /// are fed into the NVAPI flow anyway (NVAPI accepts the write — the
  /// exclusion just won't match until the exe reappears).
  Future<RulesImportResult> importFromFile(
    String filePath, {
    bool skipMissingFiles = true,
  }) async {
    final raw = await File(filePath).readAsString();
    // Convert dart:convert's raw FormatException into a user-friendly
    // message. The default one quotes the offending character index
    // plus a slice of the file, which is noise for anyone who isn't
    // reading it in a hex editor. Plan F-11 extends this treatment to
    // every JSON entry point in the app.
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException(
        'The selected file is not a valid JSON document: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a JSON object at the top level.',
      );
    }
    final RulesExportDocument doc;
    try {
      doc = RulesExportDocument.fromJson(decoded);
    } on TypeError catch (e) {
      throw FormatException(
        'Import file has the wrong shape for a rules export: $e',
      );
    }

    var imported = 0;
    var alreadyManaged = 0;
    var skippedMissing = 0;
    var failed = 0;
    final errors = <String>[];

    for (final entry in doc.rules) {
      // Normalise the path once, up front, so every subsequent decision
      // in the loop agrees. Without this, `_repo.getRuleByExePath`
      // could miss a match on a slash-variant of the same file while
      // `_addProgram.commit` (which normalises internally) would still
      // upsert to the canonical form — the import would then count it
      // as a fresh import even though a row already existed. See plan
      // F-13.
      final normalizedPath = p.normalize(entry.exePath);

      if (skipMissingFiles && !File(normalizedPath).existsSync()) {
        skippedMissing++;
        continue;
      }

      final existing = await _repo.getRuleByExePath(normalizedPath);
      final wasAlreadyManaged = existing != null;

      try {
        final result = await _addProgram.commit(normalizedPath);
        if (!result.success) {
          failed++;
          errors.add('${entry.exeName}: ${result.errorMessage ?? "failed"}');
          continue;
        }
        if (wasAlreadyManaged) {
          alreadyManaged++;
        } else {
          imported++;
        }
      } catch (e) {
        failed++;
        errors.add('${entry.exeName}: $e');
      }
    }

    return RulesImportResult(
      total: doc.rules.length,
      imported: imported,
      alreadyManaged: alreadyManaged,
      skippedMissingFile: skippedMissing,
      failed: failed,
      errors: errors,
    );
  }
}
