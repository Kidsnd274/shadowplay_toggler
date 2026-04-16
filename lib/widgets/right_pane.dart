import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../providers/managed_rule_actions_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../services/notification_service.dart';
import 'adopt_rule_button.dart';
import 'advanced_editor.dart';
import 'confirmation_dialog.dart';

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
              'External rule — not managed by this app. Adopt it to start '
              'managing it from here.',
          showAdopt: true,
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
  final bool showAdopt;

  const _ReadOnlyDetail({
    required this.rule,
    required this.subtitle,
    this.showAdopt = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderRow(rule: rule),
            const SizedBox(height: 16),
            _FieldsBlock(rule: rule),
            const SizedBox(height: 20),
            Text(subtitle, style: theme.textTheme.bodySmall),
            if (showAdopt) ...[
              const SizedBox(height: 16),
              AdoptRuleButton(rule: rule),
            ],
            const SizedBox(height: 20),
            AdvancedEditor(rule: rule, allowEdit: false),
          ],
        ),
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

enum _RuleMenuAction { unmanage, deleteProfile }

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

  bool get _exclusionEnabled =>
      widget.rule.currentValue == AppConstants.captureDisableValue;

  Future<void> _onToggle(bool enabled) async {
    final managed = _lookupManagedRule();
    if (managed == null) return;

    setState(() => _busy = true);
    final service = ref.read(managedRuleActionsServiceProvider);
    final result = await service.setExclusionEnabled(managed, enabled);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      NotificationService.showError(
        result.errorMessage ?? 'Failed to update rule.',
        context: context,
      );
      return;
    }

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;
    if (result.rowDeleted) {
      ref.read(selectedRuleProvider.notifier).state = null;
      NotificationService.showInfo(
        'Driver state was already clean; removed stale row for '
        '${managed.exeName}.',
        context: context,
      );
      return;
    }

    NotificationService.showSuccess(
      enabled
          ? 'Exclusion enabled for ${managed.exeName}.'
          : 'Exclusion cleared for ${managed.exeName}.',
      context: context,
    );
    NotificationService.showRestartTargetHint(managed.exeName, context: context);
  }

  Future<void> _onMenuAction(_RuleMenuAction action) async {
    final managed = _lookupManagedRule();
    if (managed == null) return;

    switch (action) {
      case _RuleMenuAction.unmanage:
        await _confirmUnmanage(managed);
      case _RuleMenuAction.deleteProfile:
        await _confirmDeleteProfile(managed);
    }
  }

  Future<void> _confirmUnmanage(ManagedRule managed) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Remove ${managed.exeName} from managed list?',
      message: 'The rule will be removed from this app only. The NVIDIA '
          'profile and any setting overrides stay exactly as they are on the '
          "driver — nothing is changed on NVIDIA's side. You can re-adopt "
          'this rule later from the Detected tab.',
      confirmLabel: 'Remove from list',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final service = ref.read(managedRuleActionsServiceProvider);
    final result = await service.unmanage(managed);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      NotificationService.showError(
        result.errorMessage ?? 'Failed to remove from list.',
        context: context,
      );
      return;
    }

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;
    ref.read(selectedRuleProvider.notifier).state = null;
    NotificationService.showSuccess(
      '${managed.exeName} is no longer managed by this app.',
      context: context,
    );
  }

  Future<void> _confirmDeleteProfile(ManagedRule managed) async {
    if (managed.profileWasPredefined) {
      NotificationService.showWarning(
        'Cannot delete NVIDIA-predefined profile "${managed.profileName}".',
        context: context,
      );
      return;
    }

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete NVIDIA profile "${managed.profileName}"?',
      message: 'This removes the entire profile from NVIDIA\'s driver '
          'database, including every application attached to it and every '
          'setting override on it — not just the capture-exclusion. This '
          'cannot be undone from within the app.',
      confirmLabel: 'Delete profile',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final service = ref.read(managedRuleActionsServiceProvider);
    final result = await service.deleteNvidiaProfile(managed);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      NotificationService.showError(
        result.errorMessage ?? 'Failed to delete profile.',
        context: context,
      );
      return;
    }

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;
    ref.read(selectedRuleProvider.notifier).state = null;
    NotificationService.showSuccess(
      'Deleted NVIDIA profile "${managed.profileName}".',
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPredef = widget.rule.isPredefined;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderRow(rule: widget.rule),
            const SizedBox(height: 16),
            _FieldsBlock(rule: widget.rule),
            const SizedBox(height: 20),
            _ToggleRow(
              enabled: _exclusionEnabled,
              busy: _busy,
              onChanged: _busy ? null : _onToggle,
              onMenuAction: _busy ? null : _onMenuAction,
              profileIsPredefined: isPredef,
            ),
            const SizedBox(height: 8),
            Text(
              _exclusionEnabled
                  ? 'Exclusion is active — NVIDIA capture/Instant Replay '
                      'skip this executable. Toggle off to clear the '
                      'override without losing the rule.'
                  : 'Exclusion is cleared — NVIDIA capture behaves as it '
                      'normally would for this executable. Toggle on to '
                      're-apply.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Restart the target application for changes to take full effect.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            AdvancedEditor(rule: widget.rule, allowEdit: true),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final ValueChanged<bool>? onChanged;
  final ValueChanged<_RuleMenuAction>? onMenuAction;
  final bool profileIsPredefined;

  const _ToggleRow({
    required this.enabled,
    required this.busy,
    required this.onChanged,
    required this.onMenuAction,
    required this.profileIsPredefined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exclusion enabled',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  enabled ? 'Currently hidden from capture' : 'Currently visible to capture',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (busy) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Switch(
            value: enabled,
            onChanged: onChanged,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_RuleMenuAction>(
            enabled: onMenuAction != null,
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => onMenuAction?.call(v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _RuleMenuAction.unmanage,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.playlist_remove_outlined),
                  title: Text('Remove from managed list'),
                  subtitle: Text("Local only — driver unchanged"),
                ),
              ),
              PopupMenuItem(
                value: _RuleMenuAction.deleteProfile,
                enabled: !profileIsPredefined,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: profileIsPredefined
                        ? null
                        : theme.colorScheme.error,
                  ),
                  title: Text(
                    'Delete NVIDIA profile',
                    style: TextStyle(
                      color: profileIsPredefined
                          ? null
                          : theme.colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    profileIsPredefined
                        ? 'Disabled — NVIDIA-predefined'
                        : 'Destructive — removes from NVIDIA',
                  ),
                ),
              ),
            ],
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
