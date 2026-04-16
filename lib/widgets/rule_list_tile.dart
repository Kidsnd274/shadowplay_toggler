import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';
import '../providers/selected_rule_provider.dart';

/// Which source badge to show on a list tile.
enum RuleSourceBadge { managed, external, nvidiaDefault }

/// Reusable list tile for an [ExclusionRule] in any of the left-pane tabs.
///
/// Tapping the tile selects the rule via [selectedRuleProvider] and
/// highlights the item. The optional [onSecondaryTap] callback can be wired
/// by callers to surface a right-click context menu.
class RuleListTile extends ConsumerWidget {
  final ExclusionRule rule;
  final RuleSourceBadge sourceBadge;
  final Color statusColor;
  final String? statusTooltip;
  final String? trailingHint;
  final bool dimmed;
  final VoidCallback? onSecondaryTap;

  const RuleListTile({
    super.key,
    required this.rule,
    required this.sourceBadge,
    required this.statusColor,
    this.statusTooltip,
    this.trailingHint,
    this.dimmed = false,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedRuleProvider);
    final isSelected = selected == rule;

    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: dimmed
          ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)
          : theme.textTheme.bodyMedium?.color,
    );
    final subtitleStyle = theme.textTheme.bodySmall;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(selectedRuleProvider.notifier).state = rule;
        },
        onSecondaryTapUp:
            onSecondaryTap != null ? (_) => onSecondaryTap!() : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(
                color: theme.dividerTheme.color ?? Colors.transparent,
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StatusDot(color: statusColor, tooltip: statusTooltip),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.exeName,
                      style: titleStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rule.profileName,
                      style: subtitleStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (trailingHint != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        trailingHint!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SourceBadge(source: sourceBadge),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String? tooltip;

  const _StatusDot({required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (tooltip == null) return dot;
    return Tooltip(message: tooltip!, child: dot);
  }
}

class _SourceBadge extends StatelessWidget {
  final RuleSourceBadge source;

  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, fg) = switch (source) {
      RuleSourceBadge.managed => (
          'Managed',
          theme.colorScheme.primary.withValues(alpha: 0.18),
          theme.colorScheme.primary,
        ),
      RuleSourceBadge.external => (
          'External',
          const Color(0xFFFFA000).withValues(alpha: 0.18),
          const Color(0xFFFFB74D),
        ),
      RuleSourceBadge.nvidiaDefault => (
          'Default',
          Colors.blueGrey.withValues(alpha: 0.18),
          Colors.blueGrey.shade200,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
