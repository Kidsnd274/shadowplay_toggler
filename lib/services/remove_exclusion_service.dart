import '../constants/nvapi_status.dart';
import '../models/managed_rule.dart';
import '../models/remove_result.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Clears the capture-exclusion setting for a managed rule.
///
/// This service is a thin Dart shim over the native `bridge_clear_exclusion`
/// call (which looks up the exe, decides between delete / restore-default
/// based on `isPredefinedValid`, and saves in one round trip). The UI-facing
/// contract:
///
///   * `removeExclusion(rule)` — clears the setting and, if
///     [removeFromLocalDb] is true (the "Remove Exclusion" button), deletes
///     the row from the managed-rules DB. If the exe can no longer be found
///     on the driver (stale row), the DB row is deleted unconditionally so
///     the UI stops showing a dead entry.
///   * `restoreDefault(rule)` — same NVAPI operation but keeps the DB row
///     in place so the user can re-apply without re-picking the exe.
class RemoveExclusionService {
  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;

  RemoveExclusionService(this._nvapi, this._repo);

  Future<RemoveResult> removeExclusion(
    ManagedRule rule, {
    bool removeFromLocalDb = true,
  }) async {
    Map<String, dynamic>? response;
    try {
      response = await _nvapi.clearExclusion(rule.exePath);
    } on NvapiBridgeException catch (e) {
      return RemoveResult.failure('NVAPI error: ${e.message}');
    }

    if (response == null) {
      return RemoveResult.failure('Native bridge returned no response.');
    }

    final success = (response['success'] as bool?) ?? false;
    if (!success) {
      final err = (response['error'] as String?) ?? 'unknown';
      final nvapiStatus = (response['nvapiStatus'] as num?)?.toInt();
      return RemoveResult.failure(
        humanizeNvapiStatus(nvapiStatus, 'Failed to clear exclusion: $err'),
      );
    }

    final action = (response['action'] as String?) ?? 'deleted';

    // "not_found" means the exe isn't attached to any profile anymore —
    // the driver state drifted out from under us. Treat as stale DB cleanup:
    // drop the row (always — regardless of removeFromLocalDb) because
    // keeping it would leave the UI showing a rule pointing at nothing.
    if (action == 'not_found') {
      await _deleteLocalRow(rule);
      return RemoveResult(
        success: true,
        action: 'stale_db_cleanup',
        removedFromLocalDb: true,
      );
    }

    final mappedAction = switch (action) {
      'restored' => 'setting_restored',
      'deleted' => 'setting_deleted',
      'not_set' => 'setting_deleted',
      _ => 'setting_deleted',
    };

    if (removeFromLocalDb) {
      await _deleteLocalRow(rule);
    }

    return RemoveResult(
      success: true,
      action: mappedAction,
      removedFromLocalDb: removeFromLocalDb,
    );
  }

  /// Drop the [rule] from the local DB, preferring the primary key but
  /// falling back to the exePath when [ManagedRule.id] is null.
  ///
  /// Plan F-14: callers sometimes build `ManagedRule` objects from
  /// untrusted sources (adopt flow, scan results) that have not yet
  /// been round-tripped through the repository, so they lack an id.
  /// Silently skipping the delete in that case leaves a ghost row the
  /// user has to discover via another scan.
  Future<void> _deleteLocalRow(ManagedRule rule) async {
    if (rule.id != null) {
      await _repo.deleteRule(rule.id!);
      return;
    }
    if (rule.exePath.isNotEmpty) {
      await _repo.deleteRuleByExePath(rule.exePath);
    }
  }

  /// Same NVAPI operation as [removeExclusion] but keeps the managed-rule
  /// row in the local database.
  Future<RemoveResult> restoreDefault(ManagedRule rule) =>
      removeExclusion(rule, removeFromLocalDb: false);
}
