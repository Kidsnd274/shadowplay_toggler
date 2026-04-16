import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../models/reconciliation_result.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/multi_select_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/search_provider.dart';
import 'batch_action_bar.dart';
import 'rule_list_tile.dart';

/// Managed tab content: lists rules created/managed by this app. Reads from
/// [filteredManagedRulesProvider] so the search bar in the left pane
/// transparently filters the list.
class ManagedRulesTab extends ConsumerWidget {
  const ManagedRulesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(filteredManagedRulesProvider);
    final query = ref.watch(searchProvider);
    final multiSelect = ref.watch(multiSelectModeProvider);
    final selectedIds = ref.watch(selectedRuleIdsProvider);
    final syncStatuses = ref.watch(managedRuleSyncStatusProvider);

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
            final sync = syncStatuses[managed.exePath];
            final status = _statusFor(managed, sync);
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

  /// Build the dot color / tooltip for a managed rule. Reconciliation,
  /// when it has produced a result, overrides the optimistic DB-only
  /// colour — we prefer live ground truth over the recorded `intendedValue`.
  _RuleStatus _statusFor(ManagedRule rule, ManagedRuleSyncStatus? sync) {
    if (sync != null) {
      switch (sync) {
        case ManagedRuleSyncStatus.inSync:
          return const _RuleStatus(
            color: Color(0xFF66BB6A),
            tooltip: 'In sync with NVIDIA driver',
          );
        case ManagedRuleSyncStatus.drifted:
          return const _RuleStatus(
            color: Color(0xFFFFB300),
            tooltip: 'Driver value has drifted — review this rule',
          );
        case ManagedRuleSyncStatus.orphaned:
          return const _RuleStatus(
            color: Color(0xFFE57373),
            tooltip: 'Profile or application missing from NVIDIA driver',
          );
        case ManagedRuleSyncStatus.needsReapply:
          return const _RuleStatus(
            color: Color(0xFFE57373),
            tooltip: 'Driver was reset — re-apply this rule',
          );
      }
    }

    // No reconciliation yet — fall back to the recorded intended value.
    if (rule.intendedValue == AppConstants.captureDisableValue) {
      return const _RuleStatus(
        color: Color(0xFF66BB6A),
        tooltip: 'Exclusion active (recorded)',
      );
    }
    return const _RuleStatus(
      color: Color(0xFFFFB300),
      tooltip: 'Managed — not yet verified against driver',
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
              'No managed rules yet',
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
          "No rules matching '$query'",
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
              'Failed to load rules',
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
