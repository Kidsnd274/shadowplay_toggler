import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_state_repository.dart';
import 'database_provider.dart';

/// app_state row keys used by the Settings screen. Centralised so a
/// rename is a one-line change.
abstract final class SettingsKeys {
  static const String autoScanOnLaunch = 'auto_scan_on_launch';
}

/// Persisted "auto-scan on launch" toggle. Backed by the `app_state`
/// table so it survives restarts. The HomeScreen reads this once after
/// reconciliation finishes and triggers `runScan` if true.
class AutoScanOnLaunchNotifier extends AsyncNotifier<bool> {
  late final AppStateRepository _repo;

  @override
  Future<bool> build() async {
    _repo = ref.watch(appStateRepositoryProvider);
    return _repo.getBool(SettingsKeys.autoScanOnLaunch);
  }

  /// Persist [value] first, then broadcast the new in-memory state.
  ///
  /// Plan F-21: the old order (update state, then write) meant that a
  /// failed DB write would leave the UI showing the new value while
  /// the persisted row kept the old one. A restart — or anything else
  /// re-reading the repository — would silently revert. Flipping the
  /// order keeps the two views in lockstep: if the write raises, the
  /// state stays on the previous value and the caller's snackbar path
  /// surfaces the failure.
  Future<void> set(bool value) async {
    await _repo.setBool(SettingsKeys.autoScanOnLaunch, value);
    state = AsyncValue.data(value);
  }
}

final autoScanOnLaunchProvider =
    AsyncNotifierProvider<AutoScanOnLaunchNotifier, bool>(
  AutoScanOnLaunchNotifier.new,
);
