import '../constants/app_constants.dart';
import '../constants/nvapi_status.dart';
import '../models/managed_rule.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Outcome of a single managed-rule action.
class ManagedRuleActionResult {
  final bool success;
  final String? errorMessage;

  /// Populated on success. The current [ManagedRule] row in the DB after
  /// the action, or `null` if the row was deleted.
  final ManagedRule? updatedRule;

  /// True when the local-DB row was deleted as a side effect.
  final bool rowDeleted;

  const ManagedRuleActionResult({
    required this.success,
    this.updatedRule,
    this.rowDeleted = false,
    this.errorMessage,
  });

  factory ManagedRuleActionResult.failure(String message) =>
      ManagedRuleActionResult(success: false, errorMessage: message);
}

/// Orchestrates the three actions available on the managed-rule detail
/// pane:
///
///   * [setExclusionEnabled] — toggle the 0x809D5F60 override on the
///     driver side for this rule, keeping the local-DB row in place in
///     either state so the user can flip it back on without re-picking
///     the executable.
///   * [unmanage] — drop the local-DB row only; leave the NVIDIA profile
///     and any setting overrides exactly as they are on the driver.
///   * [deleteNvidiaProfile] — destructive. Delete the whole DRS profile
///     (every application and setting on it) and drop the local-DB row.
///     Refuses to act on NVIDIA-predefined profiles — the native layer
///     also blocks this as a belt-and-braces guard.
class ManagedRuleActionsService {
  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;

  ManagedRuleActionsService(this._nvapi, this._repo);

  Future<ManagedRuleActionResult> setExclusionEnabled(
    ManagedRule rule,
    bool enabled,
  ) async {
    try {
      return enabled ? await _enable(rule) : await _disable(rule);
    } on NvapiBridgeException catch (e) {
      return ManagedRuleActionResult.failure('NVAPI error: ${e.message}');
    } catch (e) {
      return ManagedRuleActionResult.failure('Unexpected error: $e');
    }
  }

  Future<ManagedRuleActionResult> _enable(ManagedRule rule) async {
    final response = _nvapi.applyExclusion(rule.exePath);
    if (response == null || (response['success'] as bool? ?? false) == false) {
      final raw = (response?['error'] as String?) ?? 'unknown NVAPI failure';
      final code = (response?['nvapiStatus'] as num?)?.toInt();
      return ManagedRuleActionResult.failure(
        humanizeNvapiStatus(code, 'Failed to enable exclusion: $raw'),
      );
    }

    final profileName =
        (response['profileName'] as String?)?.trim().isNotEmpty == true
            ? response['profileName'] as String
            : rule.profileName;
    final profileWasPredefined =
        (response['profileWasPredefined'] as bool?) ?? rule.profileWasPredefined;
    final updated = rule.copyWith(
      profileName: profileName,
      profileWasPredefined: profileWasPredefined,
      intendedValue: AppConstants.captureDisableValue,
      updatedAt: DateTime.now(),
    );
    await _repo.insertRule(updated);
    return ManagedRuleActionResult(success: true, updatedRule: updated);
  }

  Future<ManagedRuleActionResult> _disable(ManagedRule rule) async {
    final response = _nvapi.clearExclusion(rule.exePath);
    if (response == null || (response['success'] as bool? ?? false) == false) {
      final raw = (response?['error'] as String?) ?? 'unknown NVAPI failure';
      final code = (response?['nvapiStatus'] as num?)?.toInt();
      return ManagedRuleActionResult.failure(
        humanizeNvapiStatus(code, 'Failed to disable exclusion: $raw'),
      );
    }

    // Whether the driver actually had a value to delete or it was already
    // clean, we keep the local row so the user continues to "watch" this
    // profile. The row just records intendedValue = 0 so re-enabling later
    // is one click away.
    final updated = rule.copyWith(
      intendedValue: 0,
      updatedAt: DateTime.now(),
    );
    await _repo.insertRule(updated);
    return ManagedRuleActionResult(success: true, updatedRule: updated);
  }

  /// Remove the rule from the local database. The NVIDIA profile and any
  /// setting overrides are left exactly as-is on the driver side — use this
  /// when the user wants the app to "forget" a rule without touching the
  /// underlying driver state.
  Future<ManagedRuleActionResult> unmanage(ManagedRule rule) async {
    try {
      if (rule.id != null) {
        await _repo.deleteRule(rule.id!);
      } else {
        await _repo.deleteRuleByExePath(rule.exePath);
      }
      return const ManagedRuleActionResult(success: true, rowDeleted: true);
    } catch (e) {
      return ManagedRuleActionResult.failure('Local DB error: $e');
    }
  }

  /// Delete the entire DRS profile from NVIDIA's database and drop the
  /// local-DB row. Refuses on NVIDIA-predefined profiles.
  Future<ManagedRuleActionResult> deleteNvidiaProfile(ManagedRule rule) async {
    if (rule.profileWasPredefined) {
      return ManagedRuleActionResult.failure(
        'Cannot delete NVIDIA-predefined profile "${rule.profileName}".',
      );
    }

    try {
      final response = _nvapi.deleteProfile(rule.profileName);
      if (response == null ||
          (response['success'] as bool? ?? false) == false) {
        final raw = (response?['error'] as String?) ?? 'unknown NVAPI failure';
        final code = (response?['nvapiStatus'] as num?)?.toInt();
        return ManagedRuleActionResult.failure(
          humanizeNvapiStatus(code, 'Failed to delete profile: $raw'),
        );
      }

      if (rule.id != null) {
        await _repo.deleteRule(rule.id!);
      } else {
        await _repo.deleteRuleByExePath(rule.exePath);
      }
      return const ManagedRuleActionResult(success: true, rowDeleted: true);
    } on NvapiBridgeException catch (e) {
      return ManagedRuleActionResult.failure('NVAPI error: ${e.message}');
    } catch (e) {
      return ManagedRuleActionResult.failure('Unexpected error: $e');
    }
  }
}
