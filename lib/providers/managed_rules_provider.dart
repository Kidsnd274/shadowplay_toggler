import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/managed_rule.dart';
import '../services/managed_rules_repository.dart';
import 'database_provider.dart';
import 'search_provider.dart';

/// Fetches all rules from the `ManagedRulesRepository` and exposes them as an
/// `AsyncValue<List<ManagedRule>>`. Call [ManagedRulesNotifier.refresh] to
/// re-fetch after the local database changes.
class ManagedRulesNotifier extends AsyncNotifier<List<ManagedRule>> {
  late final ManagedRulesRepository _repo;

  @override
  Future<List<ManagedRule>> build() async {
    _repo = ref.watch(managedRulesRepositoryProvider);
    return _repo.getAllRules();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.getAllRules);
  }
}

final managedRulesProvider =
    AsyncNotifierProvider<ManagedRulesNotifier, List<ManagedRule>>(
  ManagedRulesNotifier.new,
);

/// Managed rules filtered by the current search query.
///
/// Matches (case-insensitive substring) against exe name, exe path,
/// and profile name.
final filteredManagedRulesProvider =
    Provider<AsyncValue<List<ManagedRule>>>((ref) {
  final rulesAsync = ref.watch(managedRulesProvider);
  final query = ref.watch(searchProvider).trim().toLowerCase();
  if (query.isEmpty) return rulesAsync;
  return rulesAsync.whenData((rules) {
    return rules.where((r) {
      return r.exeName.toLowerCase().contains(query) ||
          r.exePath.toLowerCase().contains(query) ||
          r.profileName.toLowerCase().contains(query);
    }).toList();
  });
});
