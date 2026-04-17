import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exclusion_rule.dart';
import '../models/scan_result.dart';
import '../services/scan_service.dart';
import 'database_provider.dart';
import 'nvapi_service_provider.dart';

/// Singleton [ScanService] — it holds an in-flight future so concurrent
/// scan requests collapse into one.
final scanServiceProvider = Provider<ScanService>((ref) {
  return ScanService(
    ref.read(nvapiServiceProvider),
    ref.read(managedRulesRepositoryProvider),
  );
});

/// Whether a scan is currently running. The UI toggles this around the
/// actual `scanProfiles()` call — the service itself is internally
/// re-entrancy-safe, but the UI also needs to disable buttons and show a
/// progress indicator.
final isScanningProvider = StateProvider<bool>((ref) => false);

/// Timestamp (local time) when the most recent scan completed. Null before
/// the first scan in this session.
final lastScanAtProvider = StateProvider<DateTime?>((ref) => null);

/// The most recent [ScanResult] for the managed-drift / orphan /
/// base-profile surfaces. Detected and Defaults are pushed into their own
/// providers because the left-pane tabs already depend on them.
final lastScanResultProvider = StateProvider<ScanResult?>((ref) => null);

/// Drifted managed rules from the most recent scan, keyed by exePath for
/// quick "is this rule drifted?" lookups in the Managed tab.
final driftedManagedRulesProvider = Provider<Map<String, ExclusionRule>>((ref) {
  final result = ref.watch(lastScanResultProvider);
  if (result == null) return const {};
  return {
    for (final rule in result.driftedManagedRules) rule.exePath: rule,
  };
});

/// Orphaned managed rules (in local DB, not found in the driver) from the
/// most recent scan.
final orphanedManagedRulesProvider = Provider<Map<String, ExclusionRule>>((ref) {
  final result = ref.watch(lastScanResultProvider);
  if (result == null) return const {};
  return {
    for (final rule in result.orphanedManagedRules) rule.exePath: rule,
  };
});
