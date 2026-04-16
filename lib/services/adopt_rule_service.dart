import '../constants/app_constants.dart';
import '../models/adopt_result.dart';
import '../models/app_exception.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Moves a detected (external) rule into the local managed-rules database.
///
/// Adoption is a local-DB operation only. We re-read the live driver state
/// first so we capture the *current* value, not whatever snapshot the
/// Detected tab happened to be showing. If the profile / attachment has
/// since disappeared we refuse the adopt; the caller should kick off a
/// re-scan in that case.
class AdoptRuleService {
  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;

  AdoptRuleService(this._nvapi, this._repo);

  Future<AdoptResult> adoptRule(ExclusionRule detected) async {
    if (detected.exePath.isEmpty) {
      return AdoptResult.failure(
        'Profile-level rules without an attached executable cannot be '
        'adopted individually. This rule lives on profile '
        '"${detected.profileName}".',
      );
    }

    final existing = await _repo.getRuleByExePath(detected.exePath);
    if (existing != null) {
      return AdoptResult.alreadyManaged();
    }

    Map<String, dynamic>? findResponse;
    try {
      findResponse = _nvapi.findApplication(detected.exePath);
    } on NvapiException catch (e) {
      return AdoptResult.failure('NVAPI error: ${e.message}');
    }

    final found = (findResponse?['found'] as bool?) ?? false;
    if (!found) {
      return AdoptResult.failure(
        'Executable is no longer attached to any NVIDIA profile. Re-scan '
        'to refresh the Detected tab.',
      );
    }

    final liveProfileName =
        (findResponse?['profileName'] as String?) ?? detected.profileName;
    final liveProfileIsPredefined =
        (findResponse?['profileIsPredefined'] as bool?) ?? false;

    final profileIndex = await _resolveProfileIndex(liveProfileName);
    if (profileIndex == null) {
      return AdoptResult.failure(
        'Could not locate profile "$liveProfileName" in the DRS database.',
      );
    }

    int liveValue = detected.currentValue;
    try {
      final setting =
          _nvapi.getSetting(profileIndex, AppConstants.captureSettingId);
      if (setting != null) {
        liveValue = _parseSettingValue(setting['currentValue']) ?? liveValue;
      }
    } on NvapiException {
      // Fall back to the scan-time value. The adopt still succeeds; the
      // user will see a stale snapshot until the next scan.
    }

    final valueDrifted = liveValue != detected.currentValue;

    final now = DateTime.now();
    final rule = ManagedRule(
      exePath: detected.exePath,
      exeName: detected.exeName,
      profileName: liveProfileName,
      profileWasPredefined: liveProfileIsPredefined,
      profileWasCreated: false,
      intendedValue: liveValue,
      previousValue: liveValue,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _repo.insertRule(rule);
    } catch (e) {
      return AdoptResult.failure('Failed to persist managed rule: $e');
    }

    return AdoptResult(
      success: true,
      valueChangedSinceScan: valueDrifted,
      adoptedValue: liveValue,
    );
  }

  /// Adopt every rule in [detectedRules], collecting per-rule outcomes.
  Future<AdoptAllResult> adoptAll(List<ExclusionRule> detectedRules) async {
    var adopted = 0;
    var already = 0;
    var failed = 0;
    final errors = <String>[];

    for (final rule in detectedRules) {
      final result = await adoptRule(rule);
      if (!result.success) {
        failed++;
        errors.add('${rule.exeName}: ${result.errorMessage ?? "unknown"}');
      } else if (result.alreadyManaged) {
        already++;
      } else {
        adopted++;
      }
    }

    return AdoptAllResult(
      total: detectedRules.length,
      adopted: adopted,
      alreadyManaged: already,
      failed: failed,
      errors: errors,
    );
  }

  Future<int?> _resolveProfileIndex(String profileName) async {
    try {
      final profiles = _nvapi.getAllProfiles();
      for (final p in profiles) {
        if (p.name == profileName) return p.index;
      }
    } on NvapiException {
      return null;
    }
    return null;
  }

  int? _parseSettingValue(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) {
      final cleaned = raw.startsWith('0x') || raw.startsWith('0X')
          ? raw.substring(2)
          : raw;
      return int.tryParse(cleaned, radix: 16);
    }
    return null;
  }
}
