import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/reconciliation_result.dart';
import '../models/scan_result.dart';
import 'app_state_repository.dart';
import 'managed_rules_repository.dart';
import 'scan_service.dart';

/// Key names for reconciliation-related entries in the `app_state` table.
class ReconciliationKeys {
  ReconciliationKeys._();
  static const String lastDriverVersion = 'last_driver_version';
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
    final previousVersion =
        await _stateRepo.getValue(ReconciliationKeys.lastDriverVersion);

    // Delegate the heavy lifting to ScanService.scanProfiles(). It runs
    // the native scan on an isolate and returns the classified buckets
    // we want (detected / defaults / drifted / orphaned).
    final ScanResult scan;
    try {
      scan = await _scan.scanProfiles();
    } catch (e) {
      return ReconciliationResult.fatal('Reconciliation scan failed: $e');
    }

    if (scan.hasError) {
      return ReconciliationResult.fatal(
        scan.error ?? 'Reconciliation scan failed.',
      );
    }

    final currentHash = _hashScan(scan);
    final managed = await _rulesRepo.getAllRules();

    final drsReset = previousHash != null && previousHash != currentHash;
    final statuses = <String, ManagedRuleSyncStatus>{};

    if (drsReset) {
      for (final rule in managed) {
        statuses[rule.exePath] = ManagedRuleSyncStatus.needsReapply;
      }
      await _stateRepo.setValue(ReconciliationKeys.drsProfileHash, currentHash);
      await _stateRepo.setValue(
        ReconciliationKeys.lastReconcileAt,
        DateTime.now().toIso8601String(),
      );

      return ReconciliationResult(
        drsResetDetected: true,
        previousDriverVersion: previousVersion,
        currentDriverVersion: null,
        rulesNeedingReapply: managed.length,
        statuses: statuses,
        detectedExternalRules: scan.detectedRules,
        duration: DateTime.now().difference(started),
      );
    }

    // Normal path: classify each managed rule against the scan buckets.
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
        statuses[rule.exePath] = ManagedRuleSyncStatus.drifted;
        driftedCount++;
      } else if (orphans.containsKey(rule.exePath)) {
        statuses[rule.exePath] = ManagedRuleSyncStatus.orphaned;
        orphanedCount++;
      } else {
        statuses[rule.exePath] = ManagedRuleSyncStatus.inSync;
        inSync++;
      }
    }

    await _stateRepo.setValue(ReconciliationKeys.drsProfileHash, currentHash);
    await _stateRepo.setValue(
      ReconciliationKeys.lastReconcileAt,
      DateTime.now().toIso8601String(),
    );

    return ReconciliationResult(
      drsResetDetected: false,
      previousDriverVersion: previousVersion,
      currentDriverVersion: null,
      rulesInSync: inSync,
      rulesDrifted: driftedCount,
      rulesOrphaned: orphanedCount,
      statuses: statuses,
      detectedExternalRules: scan.detectedRules,
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

  /// 64-bit FNV-1a string hash. Not cryptographic, but plenty for
  /// "did the DRS database change?"
  int _stringHash(String s) {
    // FNV offset basis and prime for 64 bit. We stay in 63-bit signed
    // space because Dart ints on the VM are 64-bit signed — small risk
    // of overflow on web, which we don't target.
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash;
  }
}
