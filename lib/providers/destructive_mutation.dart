import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detected_rules_provider.dart';
import 'managed_rules_provider.dart';
import 'multi_select_provider.dart';
import 'nvidia_defaults_provider.dart';
import 'profile_exclusion_state_provider.dart';
import 'reconciliation_provider.dart';
import 'scan_provider.dart';
import 'selected_rule_provider.dart';

/// Shared "reset transient UI state after a destructive write" helper.
///
/// Several flows (Reset Database, Adopt All, future bulk unadopt, etc.)
/// end up invalidating every Riverpod surface that snapshots the
/// database or the driver: the currently-selected rule, multi-select
/// chips, the Detected / Defaults caches, the live exclusion map, the
/// last scan timestamp, and the reconciliation banner.
///
/// Previously each site hand-rolled the list, which meant:
///
///  * Drift — one site cleared `lastScanAtProvider` but forgot
///    `lastReconciliationProvider`, another the other way round (plan
///    F-03 / F-05 originally surfaced two separate instances of this).
///  * Skipped steps — new providers added since the original flows
///    were written never get plumbed into the older ones, producing
///    "phantom selection" bugs after reset/adopt.
///
/// Keep this helper as the single source of truth for "after something
/// destructive, what UI state must go away". Adding a new destructive
/// flow? Call this. Adding a new cache that can go stale on
/// destructive writes? Add a line here and every caller benefits.
///
/// Options:
///
///  * [clearDetected] — wipe the Detected tab cache. Default `true`.
///    Disable for flows that leave Detected intact (none today, but
///    keeps the API flexible).
///  * [clearDefaults] — wipe the Defaults tab cache. Default `false`
///    because only Reset DB needs this; Adopt All etc. leave NVIDIA
///    defaults alone.
///  * [clearLiveExclusionState] — reset [profileExclusionStateProvider]
///    to `{}`. Default `false`. The Reset flow needs this (rows are
///    gone); Adopt All does not (managed rules keep their live state).
///  * [refreshManaged] — re-query the `managed_rules` table. Default
///    `true`; a flow that has just bulk-updated the DB almost always
///    wants the UI to resync before returning.
Future<void> afterDestructiveMutation(
  WidgetRef ref, {
  bool clearDetected = true,
  bool clearDefaults = false,
  bool clearLiveExclusionState = false,
  bool refreshManaged = true,
}) async {
  if (clearDetected) {
    ref.read(detectedRulesProvider.notifier).clear();
  }
  if (clearDefaults) {
    ref.read(nvidiaDefaultsProvider.notifier).clear();
  }
  if (clearLiveExclusionState) {
    ref.read(profileExclusionStateProvider.notifier).setAll(const {});
  }

  // Selection + multi-select always reset: the id/row the user was
  // pointing at almost certainly no longer refers to the same row.
  ref.read(selectedRuleProvider.notifier).state = null;
  exitMultiSelect(ref);

  // Last-scan / last-reconciliation snapshots referenced the old DB
  // state; anything reading them now would render stale numbers. The
  // next scan or reconciliation pass will refill them.
  ref.read(lastScanResultProvider.notifier).state = null;
  ref.read(lastScanAtProvider.notifier).state = null;
  ref.read(lastReconciliationProvider.notifier).state = null;

  if (refreshManaged) {
    await ref.read(managedRulesProvider.notifier).refresh();
  }
}
