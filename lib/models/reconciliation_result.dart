import 'exclusion_rule.dart';

/// Per-managed-rule status after a reconciliation pass.
enum ManagedRuleSyncStatus {
  /// Profile exists, app is attached, setting matches the intended value.
  inSync,

  /// Profile exists and app is attached, but the setting value no longer
  /// matches the intended value. Likely edited by another tool.
  drifted,

  /// Profile is missing or app is no longer attached. The local row will
  /// still be shown so the user can decide whether to remove it.
  orphaned,

  /// Reconciliation detected a DRS reset (driver reinstall / repair) and
  /// flagged this rule for re-apply. Rules in this state are neither
  /// drifted nor orphaned — they just need the driver state to be pushed
  /// again.
  needsReapply,
}

/// Output of [ReconciliationService.reconcile].
class ReconciliationResult {
  /// True when the DRS database appears to have been wiped since the
  /// last successful reconciliation (driver reinstall or repair).
  final bool drsResetDetected;

  /// Driver version string from the previous successful reconciliation,
  /// if any. Currently best-effort — the native bridge does not yet
  /// expose driver version, so this is effectively always null until a
  /// future revision.
  final String? previousDriverVersion;

  /// Driver version string from the current reconciliation. Same caveat
  /// as [previousDriverVersion].
  final String? currentDriverVersion;

  final int rulesInSync;
  final int rulesDrifted;
  final int rulesOrphaned;
  final int rulesNeedingReapply;

  /// Per-rule sync status keyed by `exePath`. The UI joins this against
  /// `managedRulesProvider` to render status dots.
  final Map<String, ManagedRuleSyncStatus> statuses;

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
    this.previousDriverVersion,
    this.currentDriverVersion,
    this.rulesInSync = 0,
    this.rulesDrifted = 0,
    this.rulesOrphaned = 0,
    this.rulesNeedingReapply = 0,
    this.statuses = const {},
    this.detectedExternalRules = const [],
    this.warnings = const [],
    this.duration = Duration.zero,
    this.fatalError,
  });

  factory ReconciliationResult.fatal(String message) =>
      ReconciliationResult(fatalError: message);

  bool get hasFatalError => fatalError != null;

  bool get hasAnyIssue =>
      drsResetDetected ||
      rulesDrifted > 0 ||
      rulesOrphaned > 0 ||
      rulesNeedingReapply > 0;
}
