import '../constants/app_constants.dart';
import '../models/adopt_result.dart';
import '../models/app_exception.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import 'apply_exclusion_service.dart';
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
  final ApplyExclusionService _apply;

  AdoptRuleService(this._nvapi, this._repo, this._apply);

  /// Watch a previously-external profile from this app. Adoption is
  /// purely local — the NVIDIA driver is never mutated. The exclusion
  /// stays in whatever state it was in (set or cleared); the only
  /// observable change is that the row now appears in the Managed tab.
  ///
  /// To "adopt + apply the exclusion in one step", call
  /// [adoptAndAddExclusion] instead.
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

    // Best-effort: re-resolve the profile so we record the live name
    // (in case the user renamed it externally). We do *not* read the
    // setting value here — `intendedValue` is no longer used by the UI
    // for live state; it's just a starting hint.
    Map<String, dynamic>? findResponse;
    try {
      findResponse = await _nvapi.findApplication(detected.exePath);
    } on NvapiException catch (e) {
      return AdoptResult.failure('NVAPI error: ${e.message}');
    }

    final liveProfileName =
        (findResponse?['profileName'] as String?)?.trim().isNotEmpty == true
            ? findResponse!['profileName'] as String
            : detected.profileName;
    final liveProfileIsPredefined =
        (findResponse?['profileIsPredefined'] as bool?) ??
            detected.isPredefined;

    final now = DateTime.now();
    final rule = ManagedRule(
      exePath: detected.exePath,
      exeName: detected.exeName,
      profileName: liveProfileName,
      profileWasPredefined: liveProfileIsPredefined,
      profileWasCreated: false,
      intendedValue: detected.currentValue,
      previousValue: detected.currentValue,
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
      adoptedValue: detected.currentValue,
    );
  }

  /// Two-in-one: adopt the profile *and* set the capture-exclusion on
  /// the driver. Used by the "Add Exclusion" action in the Detected tab
  /// (and from the Add-Program flow when the executable was already on
  /// a profile but the exclusion wasn't set yet).
  ///
  /// Adopt-first (local DB insert) means "apply failed" still leaves
  /// the user in a sane place: the rule is watched but the driver
  /// value is whatever it was before. The [ApplyExclusionService]
  /// call is what turns the driver value on; its error message is
  /// prefixed with "Adopted, but…" so the UI can tell the user the
  /// first half worked.
  Future<AdoptResult> adoptAndAddExclusion(ExclusionRule detected) async {
    final adopt = await adoptRule(detected);
    if (!adopt.success || adopt.alreadyManaged) return adopt;

    final outcome = await _apply.apply(
      detected.exePath,
      operationLabel: 'set exclusion',
    );
    if (!outcome.success) {
      return AdoptResult.failure(
        'Adopted, but ${outcome.errorMessage ?? "failed to set exclusion."}',
      );
    }

    return AdoptResult(
      success: true,
      adoptedValue: AppConstants.captureDisableValue,
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

}
