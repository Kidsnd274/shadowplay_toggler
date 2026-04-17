import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/multi_select_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/search_provider.dart';
import 'batch_action_bar.dart';
import 'rule_list_tile.dart';

/// Managed tab content: lists NVIDIA profiles this app is watching. Reads
/// from [filteredManagedRulesProvider] so the search bar in the left pane
/// transparently filters the list.
class ManagedRulesTab extends ConsumerWidget {
  const ManagedRulesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(filteredManagedRulesProvider);
    final query = ref.watch(searchProvider);
    final multiSelect = ref.watch(multiSelectModeProvider);
    final selectedIds = ref.watch(selectedRuleIdsProvider);
    final exclusionStates = ref.watch(profileExclusionStateProvider);

    return rulesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorState(message: err.toString()),
      data: (rules) {
        if (rules.isEmpty) {
          return query.trim().isEmpty
              ? const _EmptyState()
              : _NoMatchState(query: query);
        }

        final list = ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rules.length,
          itemBuilder: (context, i) {
            final managed = rules[i];
            final exclusion = ExclusionRule.fromManagedRule(managed);
            final status = _statusFor(exclusionStates[managed.exePath]);
            final ruleId = managed.id;
            return RuleListTile(
              rule: exclusion,
              sourceBadge: RuleSourceBadge.managed,
              statusColor: status.color,
              statusTooltip: status.tooltip,
              multiSelectMode: multiSelect,
              isChecked: ruleId != null && selectedIds.contains(ruleId),
              onCheckedChanged: ruleId == null
                  ? null
                  : (checked) => _toggleSelected(ref, ruleId, checked),
              onLongPress: multiSelect
                  ? null
                  : () => _enterMultiSelect(ref, ruleId),
            );
          },
        );

        if (!multiSelect) return list;
        return Column(
          children: [
            const BatchActionBar(),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  void _toggleSelected(WidgetRef ref, int id, bool checked) {
    final current = ref.read(selectedRuleIdsProvider);
    final next = Set<int>.from(current);
    if (checked) {
      next.add(id);
    } else {
      next.remove(id);
    }
    ref.read(selectedRuleIdsProvider.notifier).state = next;
  }

  void _enterMultiSelect(WidgetRef ref, int? initialId) {
    ref.read(multiSelectModeProvider.notifier).state = true;
    ref.read(selectedRuleIdsProvider.notifier).state =
        initialId == null ? const {} : {initialId};
  }

  /// Map the live exclusion state into a status dot. We only have two
  /// signal colours: green when the exclusion is set on the driver,
  /// grey otherwise. `null` (haven't queried yet, or profile missing
  /// from the driver) is treated as "not excluded" for colouring
  /// purposes — the tooltip explains the nuance for users who hover.
  _RuleStatus _statusFor(bool? excluded) {
    const greenExcluded = Color(0xFF66BB6A);
    const neutralCleared = Color(0xFF90A4AE);
    if (excluded == true) {
      return const _RuleStatus(
        color: greenExcluded,
        tooltip: 'Exclusion active on the driver',
      );
    }
    if (excluded == false) {
      return const _RuleStatus(
        color: neutralCleared,
        tooltip: 'Watched — exclusion is cleared',
      );
    }
    return const _RuleStatus(
      color: neutralCleared,
      tooltip: 'Live state not verified yet — run Scan Profiles to refresh',
    );
  }
}

class _RuleStatus {
  final Color color;
  final String tooltip;
  const _RuleStatus({required this.color, required this.tooltip});
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rule_folder_outlined,
              size: 40,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(height: 12),
            Text(
              'No managed profiles yet',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Click 'Add Program' to get started.",
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  final String query;
  const _NoMatchState({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          "No profiles matching '$query'",
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 32,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load profiles',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
