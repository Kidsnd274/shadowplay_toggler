import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';
import 'search_provider.dart';

/// State for the "NVIDIA Defaults" tab. Tracks the predefined profiles that
/// carry setting `0x809D5F60` plus whether the user has performed a scan.
class NvidiaDefaultsState {
  final List<ExclusionRule> rules;
  final bool hasScanned;

  const NvidiaDefaultsState({
    this.rules = const [],
    this.hasScanned = false,
  });

  NvidiaDefaultsState copyWith({
    List<ExclusionRule>? rules,
    bool? hasScanned,
  }) {
    return NvidiaDefaultsState(
      rules: rules ?? this.rules,
      hasScanned: hasScanned ?? this.hasScanned,
    );
  }
}

class NvidiaDefaultsNotifier extends StateNotifier<NvidiaDefaultsState> {
  NvidiaDefaultsNotifier() : super(const NvidiaDefaultsState());

  void setRules(List<ExclusionRule> rules) {
    state = state.copyWith(rules: rules, hasScanned: true);
  }

  void clear() {
    state = const NvidiaDefaultsState();
  }
}

final nvidiaDefaultsProvider =
    StateNotifierProvider<NvidiaDefaultsNotifier, NvidiaDefaultsState>(
  (ref) => NvidiaDefaultsNotifier(),
);

/// NVIDIA defaults filtered by the current search query.
final filteredNvidiaDefaultsProvider = Provider<List<ExclusionRule>>((ref) {
  final rules = ref.watch(nvidiaDefaultsProvider).rules;
  final query = ref.watch(searchProvider).trim().toLowerCase();
  if (query.isEmpty) return rules;
  return rules.where((r) {
    return r.exeName.toLowerCase().contains(query) ||
        r.exePath.toLowerCase().contains(query) ||
        r.profileName.toLowerCase().contains(query);
  }).toList();
});
