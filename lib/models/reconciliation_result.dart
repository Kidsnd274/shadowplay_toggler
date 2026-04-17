import 'exclusion_rule.dart';

/// Output of [ReconciliationService.reconcile].
///
/// The result is intentionally coarse — per-managed-rule drift/orphan
/// state is exposed via [driftedManagedRulesProvider] and
/// [orphanedManagedRulesProvider] fed off the underlying [ScanResult],
/// and per-exe live values are published into
/// [profileExclusionStateProvider]. Everything on this class is in
/// service of the startup banner / counters; anything the Managed tab
/// needs to render row-level badges comes from the scan providers.
///
/// Driver-version tracking used to live here but was never wired up —
/// the native bridge doesn't expose `NvAPI_SYS_GetDriverAndBranchVersion`.
/// See F-08. Reintroduce the fields (and the `last_driver_version`
/// `app_state` key) together with the bridge call when that lands.
class ReconciliationResult {
  /// True when the DRS database appears to have been wiped since the
  /// last successful reconciliation (driver reinstall or repair).
  final bool drsResetDetected;

  final int rulesInSync;
  final int rulesDrifted;
  final int rulesOrphaned;
  final int rulesNeedingReapply;

  /// Live driver values for every managed exe, keyed by `exePath`. A
  /// `null` value means the exe is no longer attached to any DRS
  /// profile (orphaned). Used to hydrate
  /// `profileExclusionStateProvider` in one shot at startup.
  final Map<String, int?> managedExeLiveValues;

  /// External rules (not in local DB) surfaced by the driver scan. Shown
  /// in the Detected tab once the scan pipeline publishes them — the
  /// reconciliation service does not push these into providers directly.
  final List<ExclusionRule> detectedExternalRules;

  /// Non-fatal messages encountered during the scan (e.g. "could not
  /// resolve profile X").
  final List<String> warnings;

  final Duration duration;

  /// Non-null when reconciliation could not run at all (e.g. NVAPI
  /// unavailable). Services should surface this as a banner rather than a
  /// toast.
  final String? fatalError;

  const ReconciliationResult({
    this.drsResetDetected = false,
    this.rulesInSync = 0,
    this.rulesDrifted = 0,
    this.rulesOrphaned = 0,
    this.rulesNeedingReapply = 0,
    this.managedExeLiveValues = const {},
    this.detectedExternalRules = const [],
    this.warnings = const [],
    this.duration = Duration.zero,
    this.fatalError,
  });

  factory ReconciliationResult.fatal(String message) =>
      ReconciliationResult(fatalError: message);

  bool get hasFatalError => fatalError != null;

  /// True when the reconciliation pass produced at least one signal
  /// the user should look at — a DRS reset, drifted/orphaned managed
  /// rules, reapply-pending rules, or any non-fatal scan warning.
  ///
  /// Renamed from the original `hasAnyIssue` in F-32. "Issue" was
  /// unhelpfully generic for a result that also happens to carry the
  /// purely informational `duration` and `managedExeLiveValues`
  /// fields, and the old getter didn't include [warnings] even
  /// though a native scan warning is exactly the kind of signal a
  /// user would describe as an issue (F-33).
  bool get needsAttention =>
      drsResetDetected ||
      rulesDrifted > 0 ||
      rulesOrphaned > 0 ||
      rulesNeedingReapply > 0 ||
      warnings.isNotEmpty;

  ReconciliationResult copyWith({
    bool? drsResetDetected,
    int? rulesInSync,
    int? rulesDrifted,
    int? rulesOrphaned,
    int? rulesNeedingReapply,
    Map<String, int?>? managedExeLiveValues,
    List<ExclusionRule>? detectedExternalRules,
    List<String>? warnings,
    Duration? duration,
    String? fatalError,
  }) {
    return ReconciliationResult(
      drsResetDetected: drsResetDetected ?? this.drsResetDetected,
      rulesInSync: rulesInSync ?? this.rulesInSync,
      rulesDrifted: rulesDrifted ?? this.rulesDrifted,
      rulesOrphaned: rulesOrphaned ?? this.rulesOrphaned,
      rulesNeedingReapply: rulesNeedingReapply ?? this.rulesNeedingReapply,
      managedExeLiveValues:
          managedExeLiveValues ?? this.managedExeLiveValues,
      detectedExternalRules:
          detectedExternalRules ?? this.detectedExternalRules,
      warnings: warnings ?? this.warnings,
      duration: duration ?? this.duration,
      fatalError: fatalError ?? this.fatalError,
    );
  }
}
