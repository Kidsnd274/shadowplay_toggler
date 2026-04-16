import '../constants/app_constants.dart';
import '../models/app_exception.dart';
import '../models/batch_result.dart';
import '../models/managed_rule.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';
import 'remove_exclusion_service.dart';

/// Batch enable/disable for multiple managed rules.
///
/// Enable = apply the capture-exclusion value to the rule's profile.
/// Disable = clear the setting (restore default / delete), but keep the
/// local DB row so the rule can be re-enabled with one click.
///
/// Individual failures don't abort the batch — they are collected into
/// [BatchResult.errors] and the rest of the queue still runs. The
/// underlying native calls (`bridge_apply_exclusion` /
/// `bridge_clear_exclusion`) each save the DRS database internally, so
/// this service does not perform a separate `SaveSettings` at the end.
class BatchService {
  final NvapiService _nvapi;
  final RemoveExclusionService _removeService;
  final ManagedRulesRepository _repo;

  BatchService(this._nvapi, this._removeService, this._repo);

  Future<BatchResult> batchEnable(List<ManagedRule> rules) async {
    if (rules.isEmpty) {
      return const BatchResult(total: 0, succeeded: 0, failed: 0);
    }

    var succeeded = 0;
    var failed = 0;
    final errors = <String>[];

    for (final rule in rules) {
      try {
        final response = _nvapi.applyExclusion(rule.exePath);
        final ok = (response?['success'] as bool?) ?? false;
        if (!ok) {
          failed++;
          errors.add(
            '${rule.exeName}: ${(response?['error'] as String?) ?? "unknown failure"}',
          );
          continue;
        }

        // applyExclusion may have created a profile or re-attached the
        // app on its own; capture whatever metadata it hands back so the
        // local row stays in lockstep with the driver.
        final now = DateTime.now();
        final updated = rule.copyWith(
          intendedValue: AppConstants.captureDisableValue,
          profileWasCreated: (response?['profileWasCreated'] as bool?) ??
              rule.profileWasCreated,
          profileWasPredefined: (response?['profileWasPredefined'] as bool?) ??
              rule.profileWasPredefined,
          updatedAt: now,
        );
        if (updated.id != null) {
          await _repo.updateRule(updated);
        } else {
          await _repo.insertRule(updated);
        }
        succeeded++;
      } on NvapiException catch (e) {
        failed++;
        errors.add('${rule.exeName}: NVAPI ${e.message}');
      } catch (e) {
        failed++;
        errors.add('${rule.exeName}: $e');
      }
    }

    return BatchResult(
      total: rules.length,
      succeeded: succeeded,
      failed: failed,
      errors: errors,
    );
  }

  Future<BatchResult> batchDisable(List<ManagedRule> rules) async {
    if (rules.isEmpty) {
      return const BatchResult(total: 0, succeeded: 0, failed: 0);
    }

    var succeeded = 0;
    var failed = 0;
    final errors = <String>[];

    for (final rule in rules) {
      try {
        final result = await _removeService.restoreDefault(rule);
        if (result.success) {
          succeeded++;
        } else {
          failed++;
          errors.add(
            '${rule.exeName}: ${result.errorMessage ?? "unknown failure"}',
          );
        }
      } catch (e) {
        failed++;
        errors.add('${rule.exeName}: $e');
      }
    }

    return BatchResult(
      total: rules.length,
      succeeded: succeeded,
      failed: failed,
      errors: errors,
    );
  }
}
