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
/// pass completes. Drives the passive "driver change detected" banner.
/// Per-profile state is published separately into
/// [profileExclusionStateProvider] so widgets can read live exclusion
/// state without depending on the reconciliation result staying around.
final lastReconciliationProvider =
    StateProvider<ReconciliationResult?>((ref) => null);
