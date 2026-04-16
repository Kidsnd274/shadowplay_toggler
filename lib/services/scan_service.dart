import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../models/scan_result.dart';
import '../native/bridge_ffi.dart';
import 'managed_rules_repository.dart';

/// Top-level worker that runs inside a spawned isolate. Function pointers
/// cannot cross isolates, so we construct a brand-new [BridgeFfi] in the
/// worker against the same DLL path. The DLL's global state (notably
/// `g_session`) is shared with the parent isolate because Windows returns
/// the same handle for `LoadLibrary` on an already-loaded module.
String? _scanInIsolate(int settingId) {
  final bridge = BridgeFfi();
  return bridge.scanExclusionRules(settingId);
}

/// Orchestrates the full DRS scan described in
/// `plans/23-scan-profiles-feature.md`.
///
/// Concurrent scans are serialised via a simple guard; a second caller
/// receives the same future as the first in-flight call. The scan itself
/// runs on a worker isolate so the UI thread is never blocked.
class ScanService {
  final ManagedRulesRepository _repo;
  final int _settingId;

  Future<ScanResult>? _inflight;

  ScanService(this._repo, {int settingId = AppConstants.captureSettingId})
      : _settingId = settingId;

  bool get isScanning => _inflight != null;

  Future<ScanResult> scanProfiles() {
    final inflight = _inflight;
    if (inflight != null) return inflight;

    final future = _runScan();
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<ScanResult> _runScan() async {
    final started = DateTime.now();
    String? json;
    try {
      json = await Isolate.run(() => _scanInIsolate(_settingId));
    } catch (e) {
      return ScanResult.error('Scan failed: $e');
    }

    if (json == null || json.isEmpty) {
      return ScanResult.error(
        'Scan returned no data. Is NVAPI initialised and a session open?',
      );
    }

    Map<String, dynamic> doc;
    try {
      doc = jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return ScanResult.error('Malformed scan response: $e');
    }

    final error = doc['error'] as String?;
    if (error != null) {
      return ScanResult.error(error);
    }

    final durationMs =
        (doc['durationMs'] as num?)?.toInt() ?? _elapsedMs(started);
    final profilesScanned = (doc['profilesScanned'] as num?)?.toInt() ?? 0;
    final settingsFound = (doc['settingsFound'] as num?)?.toInt() ?? 0;

    final rawRules = (doc['rules'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(ScannedRule.fromJson)
        .toList();

    final baseRaw = doc['baseProfile'];
    final baseRule = baseRaw is Map<String, dynamic>
        ? ScannedRule.fromJson(baseRaw)
        : null;

    final managedRules = await _repo.getAllRules();
    final classification =
        _classify(scanned: rawRules, managed: managedRules);

    return ScanResult(
      detectedRules: classification.detected,
      nvidiaDefaults: classification.defaults,
      driftedManagedRules: classification.drifted,
      orphanedManagedRules: classification.orphans,
      baseProfileRule: baseRule?.toExclusionRule(sourceType: 'inherited'),
      totalProfilesScanned: profilesScanned,
      totalSettingsFound: settingsFound,
      scanDuration: Duration(milliseconds: durationMs),
    );
  }

  _ClassificationBuckets _classify({
    required List<ScannedRule> scanned,
    required List<ManagedRule> managed,
  }) {
    // Key by (lowercased exePath, profileName) for matching. NVAPI exe paths
    // are case-insensitive on Windows, which is what we are dealing with.
    final managedByKey = <String, ManagedRule>{};
    for (final rule in managed) {
      managedByKey[_key(rule.exePath, rule.profileName)] = rule;
    }

    final detected = <ExclusionRule>[];
    final defaults = <ExclusionRule>[];
    final drifted = <ExclusionRule>[];
    final seenManagedKeys = <String>{};

    for (final s in scanned) {
      if (s.appExePath.isEmpty) {
        // Profile has the setting but no attached apps. Treat as an NVIDIA
        // default if the value is predefined, otherwise a profile-level
        // external rule. Either way, no exe to tie to the managed DB.
        if (s.isCurrentPredefined) {
          defaults.add(s.toExclusionRule(sourceType: 'nvidia_default'));
        } else {
          detected.add(s.toExclusionRule(sourceType: 'external'));
        }
        continue;
      }

      final key = _key(s.appExePath, s.profileName);
      final match = managedByKey[key];
      if (match != null) {
        seenManagedKeys.add(key);
        if (match.intendedValue != s.currentValue) {
          drifted.add(ExclusionRule(
            exePath: match.exePath,
            exeName: match.exeName,
            profileName: match.profileName,
            isManaged: true,
            isPredefined: match.profileWasPredefined,
            currentValue: s.currentValue,
            previousValue: match.intendedValue,
            sourceType: 'managed',
            createdAt: match.createdAt,
            updatedAt: match.updatedAt,
          ));
        }
        // In-sync managed rules are not placed in any scan bucket; the
        // Managed tab renders them from the local DB.
        continue;
      }

      if (s.isCurrentPredefined) {
        defaults.add(s.toExclusionRule(sourceType: 'nvidia_default'));
      } else {
        detected.add(s.toExclusionRule(sourceType: 'external'));
      }
    }

    // Orphans: managed rows with no matching scanned rule.
    final orphans = <ExclusionRule>[];
    for (final entry in managedByKey.entries) {
      if (seenManagedKeys.contains(entry.key)) continue;
      final rule = entry.value;
      orphans.add(ExclusionRule(
        exePath: rule.exePath,
        exeName: rule.exeName,
        profileName: rule.profileName,
        isManaged: true,
        isPredefined: rule.profileWasPredefined,
        currentValue: rule.intendedValue,
        sourceType: 'managed',
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt,
      ));
    }

    return _ClassificationBuckets(
      detected: detected,
      defaults: defaults,
      drifted: drifted,
      orphans: orphans,
    );
  }

  String _key(String exePath, String profileName) =>
      '${exePath.toLowerCase()}|$profileName';

  int _elapsedMs(DateTime started) =>
      DateTime.now().difference(started).inMilliseconds;
}

class _ClassificationBuckets {
  final List<ExclusionRule> detected;
  final List<ExclusionRule> defaults;
  final List<ExclusionRule> drifted;
  final List<ExclusionRule> orphans;

  const _ClassificationBuckets({
    required this.detected,
    required this.defaults,
    required this.drifted,
    required this.orphans,
  });
}
