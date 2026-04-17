/// Outcome of [AdoptRuleService.adoptRule] /
/// [AdoptRuleService.adoptAndAddExclusion].
///
/// Adoption is purely local — only a row in the managed-rules DB is
/// created. `adoptAndAddExclusion` additionally calls
/// [NvapiService.applyExclusion] to flip the capture-exclusion on. The
/// main failure modes are "the row already exists" (soft no-op) and
/// "NVAPI rejected the request" (hard failure with a message for the
/// snackbar).
class AdoptResult {
  /// True if a managed-rules row exists for this exe after the call,
  /// either because we created it now or because it was already there.
  final bool success;

  /// True when the rule was already in the local managed-rules DB before
  /// the call. Callers can treat this as a soft no-op and surface a
  /// gentler notification.
  final bool alreadyManaged;

  /// The current value that was stored as the adopted rule's
  /// `intendedValue`. Hex, e.g. `0x10000000`. For pure adopts this is
  /// just the scan snapshot value; for `adoptAndAddExclusion` it is
  /// `AppConstants.captureDisableValue`.
  final int? adoptedValue;

  /// Non-null when [success] is false.
  final String? errorMessage;

  const AdoptResult({
    required this.success,
    this.alreadyManaged = false,
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
