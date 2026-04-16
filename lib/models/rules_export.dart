/// On-disk schema for an exported managed-rules JSON document.
///
/// Versioning contract:
///   * `schemaVersion` is a monotonically increasing integer.
///   * Readers MUST refuse `schemaVersion > _supportedSchemaVersion` but
///     MAY accept older schemas via explicit migrations.
///   * Added fields are optional (null-safe) so old exports still round-trip.
class RulesExportDocument {
  static const int currentSchemaVersion = 1;
  static const String formatId = 'shadowplay-toggler-managed-rules';

  final int schemaVersion;
  final String format;
  final DateTime exportedAt;
  final String? appVersion;
  final List<RulesExportEntry> rules;

  const RulesExportDocument({
    required this.schemaVersion,
    required this.format,
    required this.exportedAt,
    required this.rules,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'format': format,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        if (appVersion != null) 'appVersion': appVersion,
        'rules': rules.map((r) => r.toJson()).toList(),
      };

  factory RulesExportDocument.fromJson(Map<String, dynamic> json) {
    final schema = (json['schemaVersion'] as num?)?.toInt();
    final format = json['format'] as String?;
    if (schema == null || format == null) {
      throw const FormatException('Missing schemaVersion or format.');
    }
    if (format != formatId) {
      throw FormatException('Unexpected format: "$format".');
    }
    if (schema > currentSchemaVersion) {
      throw FormatException(
        'Export was created by a newer version of the app '
        '(schema v$schema, max supported v$currentSchemaVersion).',
      );
    }
    final rulesList = (json['rules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RulesExportEntry.fromJson)
        .toList();
    return RulesExportDocument(
      schemaVersion: schema,
      format: format,
      exportedAt:
          DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
              DateTime.now().toUtc(),
      appVersion: json['appVersion'] as String?,
      rules: rulesList,
    );
  }
}

/// A single rule inside an exported document.
class RulesExportEntry {
  final String exePath;
  final String exeName;
  final String profileName;
  final bool profileWasPredefined;
  final int intendedValue;

  const RulesExportEntry({
    required this.exePath,
    required this.exeName,
    required this.profileName,
    required this.profileWasPredefined,
    required this.intendedValue,
  });

  Map<String, dynamic> toJson() => {
        'exePath': exePath,
        'exeName': exeName,
        'profileName': profileName,
        'profileWasPredefined': profileWasPredefined,
        'intendedValue':
            '0x${intendedValue.toRadixString(16).toUpperCase().padLeft(8, '0')}',
      };

  factory RulesExportEntry.fromJson(Map<String, dynamic> json) {
    final exePath = json['exePath'] as String?;
    if (exePath == null || exePath.isEmpty) {
      throw const FormatException('Rule is missing exePath.');
    }
    return RulesExportEntry(
      exePath: exePath,
      exeName: (json['exeName'] as String?) ?? _basename(exePath),
      profileName: (json['profileName'] as String?) ?? _basename(exePath),
      profileWasPredefined:
          (json['profileWasPredefined'] as bool?) ?? false,
      intendedValue: _parseIntendedValue(json['intendedValue']),
    );
  }

  static int _parseIntendedValue(dynamic v) {
    if (v == null) return 0x10000000;
    if (v is int) return v;
    if (v is String) {
      final cleaned =
          v.startsWith('0x') || v.startsWith('0X') ? v.substring(2) : v;
      return int.tryParse(cleaned, radix: 16) ?? 0x10000000;
    }
    return 0x10000000;
  }

  static String _basename(String path) {
    final idx =
        path.lastIndexOf(RegExp(r'[\\/]'));
    return idx < 0 ? path : path.substring(idx + 1);
  }
}

/// Aggregated outcome of a rules-import run, surfaced back to the UI.
class RulesImportResult {
  final int total;
  final int imported;
  final int alreadyManaged;
  final int skippedMissingFile;
  final int failed;
  final List<String> errors;

  const RulesImportResult({
    required this.total,
    required this.imported,
    required this.alreadyManaged,
    required this.skippedMissingFile,
    required this.failed,
    this.errors = const [],
  });

  bool get hasFailures => failed > 0;
  bool get hasSkips => skippedMissingFile > 0;
}
