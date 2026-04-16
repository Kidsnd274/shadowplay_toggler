import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../models/remove_result.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/remove_exclusion_provider.dart';
import '../providers/selected_rule_provider.dart';

/// Right-hand detail pane.
///
/// This is a minimal implementation that covers Plan 22's requirement
/// ("the primary toggle should call [RemoveExclusionService] when turning
/// off an exclusion"). The richer badge/hex-editor layout described in
/// Plan 20 / Plan 25 is built on top of this shell.
class RightPane extends ConsumerWidget {
  const RightPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedRuleProvider);
    if (selected == null) {
      return const _EmptyDetail();
    }

    switch (selected.sourceType) {
      case 'managed':
        return _ManagedRuleDetail(rule: selected);
      case 'nvidia_default':
        return _ReadOnlyDetail(
          rule: selected,
          subtitle: 'NVIDIA-predefined profile. Read-only.',
        );
      case 'external':
      default:
        return _ReadOnlyDetail(
          rule: selected,
          subtitle:
              'External rule — not managed by this app. Adoption will be '
              'available in a future update.',
        );
    }
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a rule to view details',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyDetail extends StatelessWidget {
  final ExclusionRule rule;
  final String subtitle;

  const _ReadOnlyDetail({required this.rule, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(rule: rule),
          const SizedBox(height: 16),
          _FieldsBlock(rule: rule),
          const SizedBox(height: 20),
          Text(subtitle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ManagedRuleDetail extends ConsumerStatefulWidget {
  final ExclusionRule rule;
  const _ManagedRuleDetail({required this.rule});

  @override
  ConsumerState<_ManagedRuleDetail> createState() => _ManagedRuleDetailState();
}

class _ManagedRuleDetailState extends ConsumerState<_ManagedRuleDetail> {
  bool _busy = false;

  ManagedRule? _lookupManagedRule() {
    final rules = ref.read(managedRulesProvider).valueOrNull;
    if (rules == null) return null;
    return rules.firstWhere(
      (r) => r.exePath == widget.rule.exePath,
      orElse: () => ManagedRule(
        exePath: widget.rule.exePath,
        exeName: widget.rule.exeName,
        profileName: widget.rule.profileName,
        profileWasPredefined: widget.rule.isPredefined,
        profileWasCreated: false,
        intendedValue: widget.rule.currentValue,
        createdAt: widget.rule.createdAt ?? DateTime.now(),
        updatedAt: widget.rule.updatedAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> _confirmRemove() async {
    final managed = _lookupManagedRule();
    if (managed == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove exclusion for ${managed.exeName}?'),
        content: const Text(
          'The capture-exclusion setting will be cleared. The NVIDIA profile '
          'itself will be left in place, so this executable can be re-excluded '
          'quickly later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runRemove(managed, removeFromLocalDb: true);
  }

  Future<void> _confirmRestoreDefault() async {
    final managed = _lookupManagedRule();
    if (managed == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restore default for ${managed.exeName}?'),
        content: const Text(
          "The override will be cleared on the NVIDIA profile, but the rule "
          "will stay in your Managed list so you can re-enable it without "
          "picking the executable again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore Default'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runRemove(managed, removeFromLocalDb: false);
  }

  Future<void> _runRemove(ManagedRule managed,
      {required bool removeFromLocalDb}) async {
    setState(() => _busy = true);
    final service = ref.read(removeExclusionServiceProvider);

    RemoveResult result;
    try {
      result = removeFromLocalDb
          ? await service.removeExclusion(managed)
          : await service.restoreDefault(managed);
    } catch (e) {
      result = RemoveResult.failure('Unexpected error: $e');
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      await ref.read(managedRulesProvider.notifier).refresh();
      if (!mounted) return;
      if (result.removedFromLocalDb) {
        ref.read(selectedRuleProvider.notifier).state = null;
      }
      final msg = switch (result.action) {
        'stale_db_cleanup' =>
          'Driver state was already clean; removed stale row.',
        'setting_restored' =>
          'Restored NVIDIA default for ${managed.exeName}.',
        _ => 'Exclusion removed for ${managed.exeName}.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Failed to remove.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(rule: widget.rule),
          const SizedBox(height: 16),
          _FieldsBlock(rule: widget.rule),
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _confirmRemove,
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Remove Exclusion'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _confirmRestoreDefault,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore Default'),
              ),
              if (_busy) ...[
                const SizedBox(width: 16),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Restart the target application for changes to take full effect.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final ExclusionRule rule;
  const _HeaderRow({required this.rule});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rule.exeName,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(rule.exePath, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        _StatusBadge(rule: rule),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ExclusionRule rule;
  const _StatusBadge({required this.rule});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExcluded = rule.currentValue == AppConstants.captureDisableValue;
    final color = isExcluded
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final label = isExcluded ? 'Excluded' : 'Inactive';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _FieldsBlock extends StatelessWidget {
  final ExclusionRule rule;
  const _FieldsBlock({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValue('Profile', rule.profileName),
        _KeyValue(
          'Profile type',
          rule.isPredefined ? 'NVIDIA-predefined' : 'User profile',
        ),
        _KeyValue(
          'Setting ID',
          '0x${AppConstants.captureSettingId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
        ),
        _KeyValue(
          'Current value',
          '0x${rule.currentValue.toRadixString(16).toUpperCase().padLeft(8, '0')}',
        ),
        _KeyValue(
          'Source',
          switch (rule.sourceType) {
            'managed' => 'Managed by this app',
            'external' => 'External override',
            'nvidia_default' => 'NVIDIA default',
            'inherited' => 'Inherited (Base / Global)',
            _ => rule.sourceType,
          },
        ),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
