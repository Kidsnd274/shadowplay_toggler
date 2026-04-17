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
///
/// When [multiSelectMode] is true, a checkbox replaces the selection
/// highlight and taps toggle [isChecked] via [onCheckedChanged] instead of
/// mutating the detail selection. Callers also typically enter multi-select
/// via [onLongPress] (managed tab only).
class RuleListTile extends ConsumerWidget {
  final ExclusionRule rule;
  final RuleSourceBadge sourceBadge;
  final Color statusColor;
  final String? statusTooltip;
  final String? trailingHint;

  /// Optional tap handler for [trailingHint]. When provided, the hint text
  /// is rendered as an inline clickable link (underlined, accent color) and
  /// tapping it fires this callback instead of selecting the rule.
  final VoidCallback? onTrailingHintPressed;

  /// Optional custom widget shown on the right-hand side of the tile,
  /// after the source badge. Useful for inline action buttons (e.g. an
  /// "Adopt" button on detected rows). When present, the widget is
  /// responsible for its own tap handling — the list tile's `onTap` still
  /// fires for taps outside the widget.
  final Widget? trailingWidget;
  final bool dimmed;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;
  final bool multiSelectMode;
  final bool isChecked;
  final ValueChanged<bool>? onCheckedChanged;

  const RuleListTile({
    super.key,
    required this.rule,
    required this.sourceBadge,
    required this.statusColor,
    this.statusTooltip,
    this.trailingHint,
    this.onTrailingHintPressed,
    this.trailingWidget,
    this.dimmed = false,
    this.onSecondaryTap,
    this.onLongPress,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.onCheckedChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedRuleProvider);
    final isSelected = !multiSelectMode && selected == rule;

    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: dimmed
          ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)
          : theme.textTheme.bodyMedium?.color,
    );
    final subtitleStyle = theme.textTheme.bodySmall;

    final highlight = multiSelectMode && isChecked;

    return Material(
      color: (isSelected || highlight)
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (multiSelectMode) {
            onCheckedChanged?.call(!isChecked);
            return;
          }
          ref.read(selectedRuleProvider.notifier).state = rule;
        },
        onLongPress: onLongPress,
        onSecondaryTapUp:
            onSecondaryTap != null ? (_) => onSecondaryTap!() : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: (isSelected || highlight)
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
              if (multiSelectMode) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: onCheckedChanged == null
                        ? null
                        : (v) => onCheckedChanged!(v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
                      _TrailingHint(
                        label: trailingHint!,
                        onPressed: onTrailingHintPressed,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SourceBadge(source: sourceBadge),
              if (trailingWidget != null) ...[
                const SizedBox(width: 8),
                trailingWidget!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailingHint extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _TrailingHint({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontStyle: FontStyle.italic,
      decoration: onPressed != null ? TextDecoration.underline : null,
      decorationColor: theme.colorScheme.primary,
    );

    final text = Text(label, style: style);

    if (onPressed == null) return text;

    // Wrap in a MouseRegion + InkWell so the hint feels like a link and
    // its tap is consumed before the parent list tile's onTap (which would
    // otherwise just select the rule).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: text,
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
