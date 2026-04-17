import 'exclusion_rule.dart';

/// Raw rule tuple produced by `bridge_scan_exclusion_rules`. We keep the
/// live driver fields (e.g. `isPredefinedValid`, setting location) alongside
/// the flattened `ExclusionRule` the UI consumes, so classification logic
/// and reconciliation can rely on the same record without a second parse.
class ScannedRule {
  final String profileName;
  final bool profileIsPredefined;
  final String appExePath;
  final bool appIsPredefined;
  final int currentValue;
  final int predefinedValue;
  final bool isCurrentPredefined;
  final bool isPredefinedValid;
  final String settingLocation;

  const ScannedRule({
    required this.profileName,
    required this.profileIsPredefined,
    required this.appExePath,
    required this.appIsPredefined,
    required this.currentValue,
    required this.predefinedValue,
    required this.isCurrentPredefined,
    required this.isPredefinedValid,
    required this.settingLocation,
  });

  factory ScannedRule.fromJson(Map<String, dynamic> json) {
    return ScannedRule(
      profileName: (json['profileName'] as String?) ?? '',
      profileIsPredefined: (json['profileIsPredefined'] as bool?) ?? false,
      appExePath: (json['appExePath'] as String?) ?? '',
      appIsPredefined: (json['appIsPredefined'] as bool?) ?? false,
      currentValue: _parseHex(json['currentValue']),
      predefinedValue: _parseHex(json['predefinedValue']),
      isCurrentPredefined: (json['isCurrentPredefined'] as bool?) ?? false,
      isPredefinedValid: (json['isPredefinedValid'] as bool?) ?? false,
      settingLocation: (json['settingLocation'] as String?) ?? 'unknown',
    );
  }

  String get exeName {
    if (appExePath.isEmpty) return profileName;
    final i = appExePath.lastIndexOf(RegExp(r'[\\/]'));
    if (i < 0) return appExePath;
    return appExePath.substring(i + 1);
  }

  ExclusionRule toExclusionRule({required String sourceType}) {
    return ExclusionRule(
      exePath: appExePath,
      exeName: exeName,
      profileName: profileName,
      isManaged: sourceType == 'managed',
      isPredefined: profileIsPredefined,
      currentValue: currentValue,
      sourceType: sourceType,
    );
  }

  static int _parseHex(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) {
      final cleaned = raw.startsWith('0x') || raw.startsWith('0X')
          ? raw.substring(2)
          : raw;
      return int.tryParse(cleaned, radix: 16) ?? 0;
    }
    return 0;
  }
}

/// Output of [ScanService.scanProfiles]. Split into categorised buckets so
/// the UI can hand each tab its own list without re-filtering.
class ScanResult {
  final List<ExclusionRule> detectedRules;
  final List<ExclusionRule> nvidiaDefaults;
  final List<ExclusionRule> driftedManagedRules;
  final List<ExclusionRule> orphanedManagedRules;

  /// Base-profile setting state, if present. Treated as inherited behaviour
  /// by the UI; not attached to any specific exe.
  final ExclusionRule? baseProfileRule;

  /// The live driver value for every exe in the local "managed" list,
  /// keyed by `exePath`. Value is the raw DRS DWORD; `null` means the
  /// exe was not found in any profile (orphaned). Drives
  /// [profileExclusionStateProvider] and the green/grey status dot on
  /// the Managed tab.
  final Map<String, int?> managedExeLiveValues;

  final int totalProfilesScanned;
  final int totalSettingsFound;
  final Duration scanDuration;
  final String? error;

  const ScanResult({
    this.detectedRules = const [],
    this.nvidiaDefaults = const [],
    this.driftedManagedRules = const [],
    this.orphanedManagedRules = const [],
    this.baseProfileRule,
    this.managedExeLiveValues = const {},
    this.totalProfilesScanned = 0,
    this.totalSettingsFound = 0,
    this.scanDuration = Duration.zero,
    this.error,
  });

  factory ScanResult.error(String message) =>
      ScanResult(error: message);

  bool get hasError => error != null;
}
