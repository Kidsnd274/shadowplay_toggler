import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reconciliation_result.dart';
import '../models/scan_result.dart';
import 'reconciliation_provider.dart';
import 'scan_provider.dart';

/// Where the NVAPI pipeline is right now. Encodes the three mutually
/// exclusive states the rest of the UI cares about. We deliberately
/// don't model "both scanning and reconciling" — the bridge lock in
/// [NvapiService] makes that impossible, and keeping it out of the
/// type system means the UI can `switch` on [phase] exhaustively
/// without a "this shouldn't happen" branch.
enum ScanPhase {
  /// No NVAPI-touching job is running.
  idle,

  /// A full DRS scan is in flight (user-initiated or auto-on-launch).
  scanning,

  /// The startup reconciliation pass is running. This is an
  /// implicit scan + classifier + DB write, so we treat it as a
  /// distinct phase from an explicit user scan.
  reconciling,
}

/// Aggregate snapshot of every piece of "scan/reconcile" state the UI
/// needs together. Individual pieces are still exposed as their own
/// providers for fine-grained `ref.watch` / `.select()` usage —
/// [scanStateProvider] is the recommended entry point for code that
/// needs two or more of them at once (status banners, toolbar chip,
/// debug overlay), because reading them as a single snapshot avoids
/// rebuild cascades and makes call sites read top-down.
///
/// Plan item: "consolidate scan/reconcile status into one
/// scan_state_provider". The split providers were kept to avoid
/// churning every widget that only wants `isScanning`; this aggregator
/// is the consolidation point without the breakage.
class ScanState {
  const ScanState({
    required this.phase,
    required this.lastScanAt,
    required this.lastScanResult,
    required this.lastReconciliation,
  });

  /// `idle` / `scanning` / `reconciling`. See [ScanPhase].
  final ScanPhase phase;

  /// When the most recent successful scan finished. `null` before the
  /// first scan in this session. Survives across reconciliation
  /// passes (reconciliation is a scan internally but doesn't update
  /// this field — that's on purpose, the Managed tab's "Last scanned"
  /// label should reflect *user* scans).
  final DateTime? lastScanAt;

  /// Most recent explicit [ScanResult]. Mirrors `lastScanResultProvider`.
  final ScanResult? lastScanResult;

  /// Most recent [ReconciliationResult] from the startup pass.
  final ReconciliationResult? lastReconciliation;

  /// True while either a scan or a reconciliation is running. Matches
  /// [bridgeBusyProvider]; provided here so code that already watches
  /// [scanStateProvider] doesn't need a second `ref.watch`.
  bool get isBusy => phase != ScanPhase.idle;
}

/// Derived aggregate of every scan/reconcile state provider. Prefer
/// this over watching each primitive provider when you need several
/// at once.
final scanStateProvider = Provider<ScanState>((ref) {
  final scanning = ref.watch(isScanningProvider);
  final reconciling = ref.watch(isReconcilingProvider);
  final phase = scanning
      ? ScanPhase.scanning
      : reconciling
          ? ScanPhase.reconciling
          : ScanPhase.idle;
  return ScanState(
    phase: phase,
    lastScanAt: ref.watch(lastScanAtProvider),
    lastScanResult: ref.watch(lastScanResultProvider),
    lastReconciliation: ref.watch(lastReconciliationProvider),
  );
});
