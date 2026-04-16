/// Result of a single [RemoveExclusionService] call.
class RemoveResult {
  final bool success;
  final String? errorMessage;

  /// One of:
  ///   - `setting_deleted`: the setting key was removed outright.
  ///   - `setting_restored`: the setting was reset to its NVIDIA predefined
  ///     value for this profile.
  ///   - `stale_db_cleanup`: the profile was already gone from the driver,
  ///     so the local DB row was dropped without any NVAPI writes.
  ///   - `none`: nothing happened (e.g. error branch).
  final String action;

  /// Whether the managed-rule row was removed from the local database.
  final bool removedFromLocalDb;

  const RemoveResult({
    required this.success,
    required this.action,
    required this.removedFromLocalDb,
    this.errorMessage,
  });

  factory RemoveResult.failure(String message) => RemoveResult(
        success: false,
        action: 'none',
        removedFromLocalDb: false,
        errorMessage: message,
      );
}
