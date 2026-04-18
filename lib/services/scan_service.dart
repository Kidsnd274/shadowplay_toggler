import 'dart:async';
import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../models/scan_result.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Orchestrates the full DRS scan described in
/// `plans/23-scan-profiles-feature.md`.
///
/// Concurrent scans are serialised via a simple guard; a second caller
/// receives the same future as the first in-flight call. The scan itself
/// runs on a worker isolate so the UI thread is never blocked. The
/// worker's DLL entry is serialised with every other NVAPI call via the
/// shared [NvapiService] bridge lock — see
/// [NvapiService.scanExclusionRulesJsonAsync].
class ScanService {
  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;
  final int _settingId;

  Future<ScanResult>? _inflight;

  ScanService(
    this._nvapi,
    this._repo, {
    int settingId = AppConstants.captureSettingId,
  }) : _settingId = settingId;

  bool get isScanning => _inflight != null;

  /// Run a full DRS scan and return classified buckets.
  ///
  /// If [managedSnapshot] is provided, it is used verbatim for
  /// classification instead of re-querying the local DB. Reconciliation
  /// uses this to guarantee that the scan and the subsequent
  /// reconciliation pass see the same managed-rule set — a user clicking
  /// Unadopt mid-reconciliation would otherwise leave the two halves
  /// disagreeing about what's managed (F-06).
  Future<ScanResult> scanProfiles({
    List<ManagedRule>? managedSnapshot,
  }) {
    final inflight = _inflight;
    if (inflight != null) return inflight;

    final future = _runScan(managedSnapshot: managedSnapshot);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<ScanResult> _runScan({List<ManagedRule>? managedSnapshot}) async {
    final started = DateTime.now();
    String? json;
    try {
      json = await _nvapi.scanExclusionRulesJsonAsync(_settingId);
    } catch (e) {
      return ScanResult.error('Scan failed: $e');
    }

    if (json == null || json.isEmpty) {
      return ScanResult.error(
        'Scan returned no data. Is NVAPI initialised and a session open?',
      );
    }

    // Routes FormatException (bad JSON) and TypeError (right JSON,
    // wrong shape) through the same human-readable failure path so the
    // user gets "Malformed scan response" instead of a raw
    // dart:convert stack trace. Plan F-11.
    Map<String, dynamic> doc;
    try {
      doc = jsonDecode(json) as Map<String, dynamic>;
    } on FormatException catch (e) {
      return ScanResult.error('Scan returned malformed JSON: ${e.message}');
    } on TypeError catch (e) {
      return ScanResult.error(
        'Scan returned JSON with unexpected shape: $e',
      );
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

    final warnings = (doc['warnings'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);

    final managedRules = managedSnapshot ?? await _repo.getAllRules();
    final classification =
        _classify(scanned: rawRules, managed: managedRules);

    return ScanResult(
      detectedRules: classification.detected,
      nvidiaDefaults: classification.defaults,
      driftedManagedRules: classification.drifted,
      orphanedManagedRules: classification.orphans,
      baseProfileRule:
          baseRule?.toExclusionRule(source: ExclusionSource.inherited),
      managedExeLiveValues: classification.managedLiveValues,
      totalProfilesScanned: profilesScanned,
      totalSettingsFound: settingsFound,
      scanDuration: Duration(milliseconds: durationMs),
      warnings: warnings,
    );
  }

  _ClassificationBuckets _classify({
    required List<ScannedRule> scanned,
    required List<ManagedRule> managed,
  }) {
    // Key by (lowercased exePath, profileName) for matching. NVAPI exe paths
    // are case-insensitive on Windows, which is what we are dealing with.
    final managedByKey = <String, ManagedRule>{};
    // Secondary index by (basename, profileName). NVIDIA's predefined
    // profiles often ship with a bare basename attachment (e.g. the
    // "Fear The Night" profile has `moonlight.exe` attached). When the
    // user later runs Add Program with the full path
    // `L:\Apps\Moonlight\moonlight.exe`, `bridge_apply_exclusion`'s
    // `FindApplicationByName` matches the bare entry and reuses that
    // profile, so the *driver* keeps just one app row (bare name) but
    // our local DB stores the full path. The scan then comes back with
    // `appExePath = "moonlight.exe"`, which never matches the
    // full-path managed key — without this fallback the rule slides
    // into the orphan bucket and the UI flips to "Inactive" even
    // though the exclusion is correctly applied at the driver level
    // (plan F-49 / user-reported "Scan Profiles flips Excluded back to
    // Disabled").
    final managedByBasenameKey = <String, ManagedRule>{};
    for (final rule in managed) {
      managedByKey[_key(rule.exePath, rule.profileName)] = rule;
      managedByBasenameKey[_basenameKey(rule.exePath, rule.profileName)] =
          rule;
    }

    final detected = <ExclusionRule>[];
    final defaults = <ExclusionRule>[];
    final drifted = <ExclusionRule>[];
    final seenManagedKeys = <String>{};
    final managedLiveValues = <String, int?>{};

    void recordLiveForManaged(ManagedRule match, ScannedRule s) {
      managedLiveValues[match.exePath] = s.currentValue;
      if (match.intendedValue != s.currentValue) {
        drifted.add(ExclusionRule(
          exePath: match.exePath,
          exeName: match.exeName,
          profileName: match.profileName,
          isManaged: true,
          isPredefined: match.profileWasPredefined,
          currentValue: s.currentValue,
          previousValue: match.intendedValue,
          source: ExclusionSource.managed,
          createdAt: match.createdAt,
          updatedAt: match.updatedAt,
        ));
      }
    }

    for (final s in scanned) {
      if (s.appExePath.isEmpty) {
        // Profile has the setting but no attached apps. Treat as an NVIDIA
        // default if the value is predefined, otherwise a profile-level
        // external rule. Either way, no exe to tie to the managed DB.
        if (s.isCurrentPredefined) {
          defaults.add(s.toExclusionRule(source: ExclusionSource.nvidiaDefault));
        } else {
          detected.add(s.toExclusionRule(source: ExclusionSource.external));
        }
        continue;
      }

      final key = _key(s.appExePath, s.profileName);
      final match = managedByKey[key];
      if (match != null) {
        seenManagedKeys.add(key);
        recordLiveForManaged(match, s);
        // In-sync managed rules are not placed in any scan bucket; the
        // Managed tab renders them from the local DB.
        continue;
      }

      // No exact-path match. Try the basename fallback: a bare-name
      // driver row that lines up with a full-path managed row under
      // the same profile. We must hydrate the managed rule's live
      // value here too, otherwise it lands in the orphan loop with a
      // null live value and the UI renders it as Inactive.
      final basenameMatch =
          managedByBasenameKey[_basenameKey(s.appExePath, s.profileName)];
      if (basenameMatch != null) {
        final managedKey =
            _key(basenameMatch.exePath, basenameMatch.profileName);
        if (seenManagedKeys.add(managedKey)) {
          // First time we resolve this managed rule. Subsequent bare
          // and full-path duplicates under the same profile carry the
          // same `currentValue` (it's a profile-level setting), so we
          // can safely skip them.
          recordLiveForManaged(basenameMatch, s);
        }
        continue;
      }

      if (s.isCurrentPredefined) {
        defaults.add(s.toExclusionRule(source: ExclusionSource.nvidiaDefault));
      } else {
        detected.add(s.toExclusionRule(source: ExclusionSource.external));
      }
    }

    // Orphans: managed rows with no matching scanned rule.
    final orphans = <ExclusionRule>[];
    for (final entry in managedByKey.entries) {
      if (seenManagedKeys.contains(entry.key)) continue;
      final rule = entry.value;
      managedLiveValues[rule.exePath] = null;
      orphans.add(ExclusionRule(
        exePath: rule.exePath,
        exeName: rule.exeName,
        profileName: rule.profileName,
        isManaged: true,
        isPredefined: rule.profileWasPredefined,
        currentValue: rule.intendedValue,
        source: ExclusionSource.managed,
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt,
      ));
    }

    // Stable alphabetical order by exe name, then by profile name. The
    // UI relies on this so toggling state never reorders the list.
    detected.sort(_byExeThenProfile);
    defaults.sort(_byExeThenProfile);
    drifted.sort(_byExeThenProfile);
    orphans.sort(_byExeThenProfile);

    return _ClassificationBuckets(
      detected: detected,
      defaults: defaults,
      drifted: drifted,
      orphans: orphans,
      managedLiveValues: managedLiveValues,
    );
  }

  String _key(String exePath, String profileName) =>
      '${exePath.toLowerCase()}|$profileName';

  /// Strips the directory portion off `exePath` and lowercases for
  /// case-insensitive matching against another rule on the same profile.
  String _basenameKey(String exePath, String profileName) {
    final cleaned = exePath.replaceAll('\\', '/');
    final slash = cleaned.lastIndexOf('/');
    final basename =
        slash == -1 ? cleaned : cleaned.substring(slash + 1);
    return '${basename.toLowerCase()}|$profileName';
  }

  int _byExeThenProfile(ExclusionRule a, ExclusionRule b) {
    final byName =
        a.exeName.toLowerCase().compareTo(b.exeName.toLowerCase());
    if (byName != 0) return byName;
    return a.profileName.toLowerCase().compareTo(b.profileName.toLowerCase());
  }

  int _elapsedMs(DateTime started) =>
      DateTime.now().difference(started).inMilliseconds;
}

class _ClassificationBuckets {
  final List<ExclusionRule> detected;
  final List<ExclusionRule> defaults;
  final List<ExclusionRule> drifted;
  final List<ExclusionRule> orphans;
  final Map<String, int?> managedLiveValues;

  const _ClassificationBuckets({
    required this.detected,
    required this.defaults,
    required this.drifted,
    required this.orphans,
    required this.managedLiveValues,
  });
}
