import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';
import 'search_provider.dart';

/// State for the "Detected" tab. Tracks both the rule list and whether a
/// scan has been performed (so the UI can distinguish "pre-scan empty"
/// from "scanned, nothing found").
class DetectedRulesState {
  final List<ExclusionRule> rules;
  final bool hasScanned;

  const DetectedRulesState({
    this.rules = const [],
    this.hasScanned = false,
  });

  DetectedRulesState copyWith({
    List<ExclusionRule>? rules,
    bool? hasScanned,
  }) {
    return DetectedRulesState(
      rules: rules ?? this.rules,
      hasScanned: hasScanned ?? this.hasScanned,
    );
  }
}

class DetectedRulesNotifier extends StateNotifier<DetectedRulesState> {
  DetectedRulesNotifier() : super(const DetectedRulesState());

  /// Replace the rule list and mark the tab as scanned.
  void setRules(List<ExclusionRule> rules) {
    state = state.copyWith(rules: rules, hasScanned: true);
  }

  /// Reset to the pre-scan empty state.
  void clear() {
    state = const DetectedRulesState();
  }
}

final detectedRulesProvider =
    StateNotifierProvider<DetectedRulesNotifier, DetectedRulesState>(
  (ref) => DetectedRulesNotifier(),
);

/// Detected rules filtered by the current search query.
final filteredDetectedRulesProvider = Provider<List<ExclusionRule>>((ref) {
  final rules = ref.watch(detectedRulesProvider).rules;
  final query = ref.watch(searchProvider).trim().toLowerCase();
  if (query.isEmpty) return rules;
  return rules.where((r) {
    return r.exeName.toLowerCase().contains(query) ||
        r.exePath.toLowerCase().contains(query) ||
        r.profileName.toLowerCase().contains(query);
  }).toList();
});
