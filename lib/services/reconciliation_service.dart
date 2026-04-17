import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../models/reconciliation_result.dart';
import '../models/scan_result.dart';
import 'app_state_repository.dart';
import 'log_buffer.dart';
import 'managed_rules_repository.dart';
import 'scan_service.dart';

/// Key names for reconciliation-related entries in the `app_state` table.
///
/// `last_driver_version` used to live here but the native bridge does
/// not expose a driver-version query, so it was never written. The
/// corresponding `previousDriverVersion` / `currentDriverVersion`
/// fields were dropped from [ReconciliationResult] in F-08; add them
/// back only if/when the bridge gains a real driver-version query.
class ReconciliationKeys {
  ReconciliationKeys._();
  static const String drsProfileHash = 'drs_profile_hash';
  static const String lastReconcileAt = 'last_reconcile_at';
}

/// Runs the startup reconciliation pass described in
/// `plans/26-startup-reconciliation.md`.
///
/// This service is intentionally a thin orchestrator over [ScanService] —
/// the scan already walks every DRS profile on a background isolate and
/// hands back both the raw per-profile data (for hashing) and the
/// classified buckets we need to decide drift vs. orphan. We add the
/// DRS-reset detection and the `syncStatus` mapping on top.
class ReconciliationService {
  final ScanService _scan;
  final ManagedRulesRepository _rulesRepo;
  final AppStateRepository _stateRepo;

  ReconciliationService(this._scan, this._rulesRepo, this._stateRepo);

  Future<ReconciliationResult> reconcile() async {
    final started = DateTime.now();
    final previousHash =
        await _stateRepo.getValue(ReconciliationKeys.drsProfileHash);

    // Snapshot the managed-rules table once and reuse it below. If the
    // user mutates the DB (Unadopt, batch, reset) between the scan's
    // classification pass and the status computation here, we would
    // otherwise build a [statuses] map against a different set of
    // rows than the scan saw — producing e.g. "inSync" for an exe that
    // no longer exists in the DB (F-06).
    final List<ManagedRule> managed;
    try {
      managed = await _rulesRepo.getAllRules();
    } catch (e) {
      return ReconciliationResult.fatal('Failed to load managed rules: $e');
    }

    // Delegate the heavy lifting to ScanService.scanProfiles(). It runs
    // the native scan on an isolate and returns the classified buckets
    // we want (detected / defaults / drifted / orphaned). We hand it the
    // snapshot we just took so both halves agree on the managed set.
    final ScanResult scan;
    try {
      scan = await _scan.scanProfiles(managedSnapshot: managed);
    } catch (e) {
      return ReconciliationResult.fatal('Reconciliation scan failed: $e');
    }

    if (scan.hasError) {
      return ReconciliationResult.fatal(
        scan.error ?? 'Reconciliation scan failed.',
      );
    }

    // Forward any native-side warnings to the log buffer so the Logs
    // screen has a persistent record even though the startup banner
    // doesn't surface them visually. Keeps F-33's "warnings" field
    // meaningful instead of letting it quietly pile up in memory.
    for (final w in scan.warnings) {
      LogBuffer.instance.add(LogLevel.warn, '[reconcile] $w');
    }

    final currentHash = _hashScan(scan);

    final drsReset = previousHash != null && previousHash != currentHash;

    if (drsReset) {
      await _stateRepo.setValues({
        ReconciliationKeys.drsProfileHash: currentHash,
        ReconciliationKeys.lastReconcileAt: DateTime.now().toIso8601String(),
      });

      return ReconciliationResult(
        drsResetDetected: true,
        rulesNeedingReapply: managed.length,
        managedExeLiveValues: scan.managedExeLiveValues,
        detectedExternalRules: scan.detectedRules,
        warnings: scan.warnings,
        duration: DateTime.now().difference(started),
      );
    }

    // Normal path: classify each managed rule against the scan buckets
    // to produce the banner counters. Per-rule sync status is not
    // persisted on the result — anything row-level the Managed tab
    // needs is already exposed via driftedManagedRulesProvider /
    // orphanedManagedRulesProvider (see F-07).
    final drifted = {
      for (final r in scan.driftedManagedRules) r.exePath: r,
    };
    final orphans = {
      for (final r in scan.orphanedManagedRules) r.exePath: r,
    };

    var inSync = 0;
    var driftedCount = 0;
    var orphanedCount = 0;
    for (final rule in managed) {
      if (drifted.containsKey(rule.exePath)) {
        driftedCount++;
      } else if (orphans.containsKey(rule.exePath)) {
        orphanedCount++;
      } else {
        inSync++;
      }
    }

    await _stateRepo.setValues({
      ReconciliationKeys.drsProfileHash: currentHash,
      ReconciliationKeys.lastReconcileAt: DateTime.now().toIso8601String(),
    });

    return ReconciliationResult(
      drsResetDetected: false,
      rulesInSync: inSync,
      rulesDrifted: driftedCount,
      rulesOrphaned: orphanedCount,
      managedExeLiveValues: scan.managedExeLiveValues,
      detectedExternalRules: scan.detectedRules,
      warnings: scan.warnings,
      duration: DateTime.now().difference(started),
    );
  }

  /// Derive a deterministic hash from the scan result that we can use to
  /// detect "everything was wiped between sessions" without access to the
  /// driver version string.
  ///
  /// Sensitive to: total rule counts (detected + defaults + drifted +
  /// orphaned), the base-profile rule, and the sorted `(profile, exe)`
  /// pairs of each bucket. Insensitive to scan duration and ordering.
  String _hashScan(ScanResult scan) {
    String key(ExclusionRule r) => '${r.profileName}|${r.exePath}';
    List<String> sortedKeys(List<ExclusionRule> rules) {
      final keys = rules.map(key).toList()..sort();
      return keys;
    }

    final payload = {
      'detected': sortedKeys(scan.detectedRules),
      'defaults': sortedKeys(scan.nvidiaDefaults),
      'drifted': sortedKeys(scan.driftedManagedRules),
      'orphans': sortedKeys(scan.orphanedManagedRules),
      'base': scan.baseProfileRule == null ? null : key(scan.baseProfileRule!),
      'profilesScanned': scan.totalProfilesScanned,
      'settingsFound': scan.totalSettingsFound,
      'settingId': AppConstants.captureSettingId,
    };
    return _stringHash(jsonEncode(payload)).toRadixString(16);
  }

  /// Modified FNV-1a string hash, 63-bit (see below). Not
  /// cryptographic, but plenty for "did the DRS database change?"
  ///
  /// Plan F-50: the original docstring claimed this was 64-bit
  /// FNV-1a, but strict FNV-1a would mask to `0xFFFFFFFFFFFFFFFF`.
  /// We mask to `0x7FFFFFFFFFFFFFFF` so the result always fits in a
  /// positive signed 64-bit int on native Dart (avoiding overflow
  /// into a negative `toRadixString` that would cosmetically flap the
  /// stored hash value between runs). The result is deterministic and
  /// stable across Dart VM versions, which is all this function
  /// needs — we're detecting DRS-reset drift, not proving collision
  /// resistance — but it's a modified FNV variant, not textbook FNV.
  int _stringHash(String s) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash;
  }
}
