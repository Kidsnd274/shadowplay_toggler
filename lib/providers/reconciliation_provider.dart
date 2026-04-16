import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reconciliation_result.dart';
import '../services/reconciliation_service.dart';
import 'database_provider.dart';
import 'scan_provider.dart';

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  return ReconciliationService(
    ref.read(scanServiceProvider),
    ref.read(managedRulesRepositoryProvider),
    ref.read(appStateRepositoryProvider),
  );
});

/// True while the startup reconciliation pass is running. The toolbar
/// uses this to show a "Reconciling…" indicator without blocking the
/// first frame of the UI.
final isReconcilingProvider = StateProvider<bool>((ref) => false);

/// The most recent reconciliation outcome. Null until the first startup
/// pass completes. The managed list renders `syncStatus` by joining its
/// rows against [ReconciliationResult.statuses].
final lastReconciliationProvider =
    StateProvider<ReconciliationResult?>((ref) => null);

/// Per-managed-rule sync status map, derived from the most recent
/// reconciliation. Empty before the first pass or after a fatal error.
final managedRuleSyncStatusProvider =
    Provider<Map<String, ManagedRuleSyncStatus>>((ref) {
  final latest = ref.watch(lastReconciliationProvider);
  if (latest == null || latest.hasFatalError) return const {};
  return latest.statuses;
});
