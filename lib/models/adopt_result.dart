/// Outcome of [AdoptRuleService.adoptRule].
///
/// Adoption is never "destructive" at the driver level — it only writes a
/// row to the local managed-rules database. The main failure modes are
/// "the rule vanished between scan time and adoption" (e.g. another tool
/// deleted the profile) and "the row already exists in the local DB".
class AdoptResult {
  /// True if a managed-rules row exists for this exe after the call,
  /// either because we created it now or because it was already there.
  final bool success;

  /// True when the rule was already in the local managed-rules DB before
  /// the call. Callers can treat this as a soft no-op and surface a
  /// gentler notification.
  final bool alreadyManaged;

  /// True when the live driver read showed a different value than the
  /// scan snapshot the caller passed in. The local row is written with
  /// the *live* value, not the stale one; the caller may want to warn
  /// the user so they know what they actually took ownership of.
  final bool valueChangedSinceScan;

  /// The live current value that was stored as the adopted rule's
  /// `intendedValue` / `previousValue`. Hex, e.g. `0x10000000`.
  final int? adoptedValue;

  /// Non-null when [success] is false.
  final String? errorMessage;

  const AdoptResult({
    required this.success,
    this.alreadyManaged = false,
    this.valueChangedSinceScan = false,
    this.adoptedValue,
    this.errorMessage,
  });

  factory AdoptResult.failure(String message) =>
      AdoptResult(success: false, errorMessage: message);

  factory AdoptResult.alreadyManaged() =>
      const AdoptResult(success: true, alreadyManaged: true);
}

/// Aggregate result for an "Adopt All" batch.
class AdoptAllResult {
  final int total;
  final int adopted;
  final int alreadyManaged;
  final int failed;
  final List<String> errors;

  const AdoptAllResult({
    required this.total,
    required this.adopted,
    required this.alreadyManaged,
    required this.failed,
    this.errors = const [],
  });
}
