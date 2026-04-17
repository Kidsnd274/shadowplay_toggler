import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the managed list is currently in multi-select mode. When true,
/// tapping a rule toggles its selection instead of opening the detail
/// view, and the batch action bar is visible.
final multiSelectModeProvider = StateProvider<bool>((ref) => false);

/// Set of managed-rule ids currently selected in multi-select mode.
final selectedRuleIdsProvider = StateProvider<Set<int>>((ref) => const {});

/// Clear selection + exit multi-select mode in one call.
void exitMultiSelect(WidgetRef ref) {
  ref.read(multiSelectModeProvider.notifier).state = false;
  ref.read(selectedRuleIdsProvider.notifier).state = const {};
}
