import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/search_provider.dart';
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

    return rulesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorState(message: err.toString()),
      data: (rules) {
        if (rules.isEmpty) {
          return query.trim().isEmpty
              ? const _EmptyState()
              : _NoMatchState(query: query);
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rules.length,
          itemBuilder: (context, i) {
            final managed = rules[i];
            final exclusion = ExclusionRule.fromManagedRule(managed);
            final status = _statusFor(managed);
            return RuleListTile(
              rule: exclusion,
              sourceBadge: RuleSourceBadge.managed,
              statusColor: status.color,
              statusTooltip: status.tooltip,
            );
          },
        );
      },
    );
  }

  _RuleStatus _statusFor(ManagedRule rule) {
    // Plan 16 leaves driver-state verification to a later feature (NVAPI
    // service wiring). Until then, if the recorded intended value matches
    // the capture-disable value we show green; otherwise we show yellow to
    // signal "managed but unverified". Drift (red) will be surfaced once
    // the NVAPI side publishes live values in plan 26.
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
