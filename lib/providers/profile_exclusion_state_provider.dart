import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../models/managed_rule.dart';
import '../models/scan_result.dart';
import '../services/nvapi_service.dart';
import 'nvapi_service_provider.dart';

/// Single source of truth for "is the capture-exclusion active on the
/// driver right now?", keyed by the watched executable's `exePath`.
///
/// * `true`  — exclusion is set (`captureDisableValue` on the driver).
/// * `false` — profile/exe exists, but the setting is cleared or
///             absent.
/// * `null`  — unknown: the exe is not attached to any driver profile
///             yet, the live query failed, or the entry hasn't been
///             refreshed since startup.
///
/// Every visual surface that needs to render exclusion state — the
/// status dot in the Managed list, the toggle in the right-hand detail
/// pane, the "Excluded / Inactive" badge — should read from this map
/// instead of looking at `ManagedRule.intendedValue`. The DB row is
/// just the persisted "I'm watching this exe" intent; the live state
/// is queried from NVAPI on startup, on user-initiated refresh / scan,
/// and after every action that mutates driver state.
class ProfileExclusionStateNotifier
    extends StateNotifier<Map<String, bool?>> {
  /// Lazy NVAPI accessor. We don't want construction of this notifier
  /// to eagerly resolve the bridge / load the DLL — widget tests build
  /// the same widget tree without a real GPU. The accessor is invoked
  /// on demand from [refreshExe] / [refreshAll] only.
  final NvapiService Function() _nvapiResolver;

  ProfileExclusionStateNotifier(this._nvapiResolver) : super(const {});

  NvapiService get _nvapi => _nvapiResolver();

  /// Optimistically set the cached state for [exePath]. Use this from
  /// action handlers right after a successful NVAPI mutation so the UI
  /// updates without waiting for a re-scan.
  void setForExe(String exePath, bool? excluded) {
    final next = Map<String, bool?>.from(state);
    next[exePath] = excluded;
    state = Map.unmodifiable(next);
  }

  /// Drop a single entry — used after Unadopt / Delete Profile so the
  /// stale cached state doesn't keep colouring an already-removed row.
  void removeForExe(String exePath) {
    if (!state.containsKey(exePath)) return;
    final next = Map<String, bool?>.from(state)..remove(exePath);
    state = Map.unmodifiable(next);
  }

  /// Replace the whole map (used by the scan / reconciliation hydration
  /// helpers that recompute every entry).
  void setAll(Map<String, bool?> next) {
    state = Map.unmodifiable(Map<String, bool?>.from(next));
  }

  /// Translate a [ScanResult]'s live-value map into bool? entries and
  /// publish in one shot. The scan already walked every DRS profile so
  /// this is the cheap hot path used by both startup reconciliation and
  /// user-initiated scans.
  void hydrateFromScan(ScanResult scan) {
    final next = <String, bool?>{};
    scan.managedExeLiveValues.forEach((exePath, value) {
      next[exePath] = value == null
          ? null
          : value == AppConstants.captureDisableValue;
    });
    state = Map.unmodifiable(next);
  }

  /// Live-query a single [exePath]. Returns the new bool? state and
  /// updates the cache. Best-effort — any NVAPI error is mapped to
  /// `null` rather than thrown, because the caller is usually a UI
  /// action handler.
  Future<bool?> refreshExe(String exePath) async {
    final live = await _queryLive(exePath);
    setForExe(exePath, live);
    return live;
  }

  /// Live-query every exe in [rules], one round-trip each. Used as the
  /// fallback when no scan is available (e.g. immediately after Adopt
  /// inserts a row outside of a scan context).
  Future<void> refreshAll(Iterable<ManagedRule> rules) async {
    final next = Map<String, bool?>.from(state);
    for (final rule in rules) {
      next[rule.exePath] = await _queryLive(rule.exePath);
    }
    state = Map.unmodifiable(next);
  }

  /// Resolve the live driver state for [exePath]. Walks
  /// [NvapiService.findApplication] → [NvapiService.getAllProfiles] →
  /// [NvapiService.getSetting]. Returns `null` if any step fails or the
  /// exe is not attached to a profile.
  Future<bool?> _queryLive(String exePath) async {
    if (exePath.isEmpty) return null;
    try {
      final found = _nvapi.findApplication(exePath);
      if (found == null) return null;
      final attached = (found['found'] as bool?) ?? false;
      if (!attached) return null;
      final profileName = (found['profileName'] as String?) ?? '';
      if (profileName.isEmpty) return null;

      final profiles = _nvapi.getAllProfiles();
      int? profileIndex;
      for (final p in profiles) {
        if (p.name == profileName) {
          profileIndex = p.index;
          break;
        }
      }
      if (profileIndex == null) return null;

      final setting =
          _nvapi.getSetting(profileIndex, AppConstants.captureSettingId);
      if (setting == null) return false;
      final value = _parseSettingValue(setting['currentValue']);
      if (value == null) return false;
      return value == AppConstants.captureDisableValue;
    } catch (_) {
      return null;
    }
  }

  int? _parseSettingValue(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) {
      final cleaned = raw.startsWith('0x') || raw.startsWith('0X')
          ? raw.substring(2)
          : raw;
      return int.tryParse(cleaned, radix: 16);
    }
    return null;
  }
}

final profileExclusionStateProvider = StateNotifierProvider<
    ProfileExclusionStateNotifier, Map<String, bool?>>((ref) {
  return ProfileExclusionStateNotifier(() => ref.read(nvapiServiceProvider));
});
