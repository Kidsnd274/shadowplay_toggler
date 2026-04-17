import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/managed_rule_actions_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../services/notification_service.dart';
import 'adopt_rule_button.dart';
import 'advanced_editor.dart';
import 'confirmation_dialog.dart';

/// Right-hand detail pane for the currently selected rule.
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
              'External profile — not managed by this app. Adopt it to '
              'start watching it from here, or click "Add Exclusion" to '
              'adopt and turn the exclusion on in one step.',
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
    // Pinned to the top with comfortable breathing room. The user's mental
    // model is "the detail pane reads top-down", so anchoring the empty
    // hint at the top matches the loaded state's layout.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a profile to view details',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyDetail extends ConsumerWidget {
  final ExclusionRule rule;
  final String subtitle;
  final bool showAdopt;

  const _ReadOnlyDetail({
    required this.rule,
    required this.subtitle,
    this.showAdopt = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderRow(rule: rule, excluded: rule.currentValue ==
                AppConstants.captureDisableValue),
            const SizedBox(height: 16),
            _FieldsBlock(rule: rule, effectiveValue: rule.currentValue),
            const SizedBox(height: 20),
            Text(subtitle, style: theme.textTheme.bodySmall),
            if (showAdopt) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  AdoptRuleButton(rule: rule),
                  const SizedBox(width: 12),
                  _AddExclusionDetailButton(rule: rule),
                ],
              ),
            ],
            const SizedBox(height: 20),
            AdvancedEditor(rule: rule, allowEdit: false),
          ],
        ),
      ),
    );
  }
}

class _AddExclusionDetailButton extends ConsumerStatefulWidget {
  final ExclusionRule rule;
  const _AddExclusionDetailButton({required this.rule});

  @override
  ConsumerState<_AddExclusionDetailButton> createState() =>
      _AddExclusionDetailButtonState();
}

class _AddExclusionDetailButtonState
    extends ConsumerState<_AddExclusionDetailButton> {
  bool _busy = false;

  Future<void> _onPressed() async {
    setState(() => _busy = true);
    try {
      await addExclusionInteractive(context, ref, widget.rule);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _onPressed,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.visibility_off_outlined, size: 16),
      label: const Text('Add Exclusion'),
    );
  }
}

class _ManagedRuleDetail extends ConsumerStatefulWidget {
  final ExclusionRule rule;
  const _ManagedRuleDetail({required this.rule});

  @override
  ConsumerState<_ManagedRuleDetail> createState() => _ManagedRuleDetailState();
}

enum _RuleMenuAction { unadopt, deleteProfile }

class _ManagedRuleDetailState extends ConsumerState<_ManagedRuleDetail> {
  bool _busy = false;

  /// Refuse bridge-touching row mutations while a scan or the startup
  /// reconciliation is running — see plan F-16. The toggle/unadopt/menu
  /// are already greyed out by watching [bridgeBusyProvider] in the
  /// build, but this guards racy paths (keyboard, first-frame clicks).
  bool _assertBridgeFree() {
    if (!ref.read(bridgeBusyProvider)) return true;
    final reconciling = ref.read(isReconcilingProvider);
    final msg = reconciling
        ? 'Startup reconciliation is still running — try again in a moment.'
        : 'A scan is in progress — try again in a moment.';
    NotificationService.showInfo(msg, context: context);
    return false;
  }

  /// Finds the live [ManagedRule] row that backs `widget.rule`.
  ///
  /// Returns `null` when the rules list doesn't contain an entry for
  /// this exePath. The caller must interpret that correctly:
  ///
  ///   * `rules == null` → the [managedRulesProvider] hasn't emitted
  ///     yet (first frame after startup). Show a spinner instead of
  ///     synthesising a ghost row — a synthesised row would let the
  ///     toggle/unadopt/delete actions fire against stale data.
  ///   * `rules != null && result == null` → the row was deleted out
  ///     from under the selection (e.g. via Unadopt from another pane,
  ///     Reset Database, or a reconciliation orphan-removal). Clear the
  ///     selection so [RightPane] falls back to the empty state instead
  ///     of rendering against a fabricated rule.
  ManagedRule? _findManaged(List<ManagedRule> rules) {
    for (final r in rules) {
      if (r.exePath == widget.rule.exePath) return r;
    }
    return null;
  }

  Future<void> _onToggle(ManagedRule managed, bool enabled) async {
    if (!_assertBridgeFree()) return;
    setState(() => _busy = true);
    final service = ref.read(managedRuleActionsServiceProvider);
    final result = await service.setExclusionEnabled(managed, enabled);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      NotificationService.showError(
        result.errorMessage ?? 'Failed to update profile.',
        context: context,
      );
      // The optimistic state we set may have been wrong; re-query.
      await ref
          .read(profileExclusionStateProvider.notifier)
          .refreshExe(managed.exePath);
      return;
    }

    // The driver state now matches what we just wrote.
    ref
        .read(profileExclusionStateProvider.notifier)
        .setForExe(managed.exePath, enabled);

    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;

    NotificationService.showSuccess(
      enabled
          ? 'Exclusion enabled for ${managed.exeName}.'
          : 'Exclusion cleared for ${managed.exeName}.',
      context: context,
    );
    NotificationService.showRestartTargetHint(
      managed.exeName,
      context: context,
    );
  }

  Future<void> _onMenuAction(
    ManagedRule managed,
    _RuleMenuAction action,
  ) async {
    switch (action) {
      case _RuleMenuAction.unadopt:
        await _confirmUnadopt(managed);
      case _RuleMenuAction.deleteProfile:
        await _confirmDeleteProfile(managed);
    }
  }

  Future<void> _confirmUnadopt(ManagedRule managed) async {
    if (!_assertBridgeFree()) return;
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Unadopt ${managed.exeName}?',
      message: 'Stop watching this profile from this app. The NVIDIA '
          'profile and any setting overrides stay exactly as they are on '
          "the driver — nothing is changed on NVIDIA's side. If the "
          'exclusion is still set, the profile will reappear in the '
          'Detected tab so you can re-adopt it later.',
      confirmLabel: 'Unadopt',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final service = ref.read(managedRuleActionsServiceProvider);
    final result = await service.unmanage(managed);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      NotificationService.showError(
        result.errorMessage ?? 'Failed to unadopt.',
        context: context,
      );
      return;
    }

    final wasExcluded =
        ref.read(profileExclusionStateProvider)[managed.exePath] ?? false;

    ref
        .read(profileExclusionStateProvider.notifier)
        .removeForExe(managed.exePath);
    await ref.read(managedRulesProvider.notifier).refresh();
    if (!mounted) return;

    // If the exclusion is still live on the driver, surface it back in
    // the Detected tab immediately so the user sees "where it went".
    if (wasExcluded) {
      ref.read(detectedRulesProvider.notifier).addOrUpdateRule(
            ExclusionRule(
              exePath: managed.exePath,
              exeName: managed.exeName,
              profileName: managed.profileName,
              isManaged: false,
              isPredefined: managed.profileWasPredefined,
              currentValue: AppConstants.captureDisableValue,
              sourceType: 'external',
              createdAt: managed.createdAt,
              updatedAt: managed.updatedAt,
            ),
          );
    }

    ref.read(selectedRuleProvider.notifier).state = null;
    NotificationService.showSuccess(
      '${managed.exeName} is no longer watched by this app.',
      context: context,
    );
  }

  Future<void> _confirmDeleteProfile(ManagedRule managed) async {
    if (!_assertBridgeFree()) return;
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
          'setting override on it — not just the capture-exclusion. The '
          'profile is also unadopted from this app. This cannot be undone '
          'from within the app.',
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

    ref
        .read(profileExclusionStateProvider.notifier)
        .removeForExe(managed.exePath);
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
    final managedRulesAsync = ref.watch(managedRulesProvider);
    final managedRules = managedRulesAsync.valueOrNull;

    // First frame after startup — the rules query is still in flight.
    // Rendering anything meaningful would require synthesising a
    // ManagedRule, which is the exact bug F-04 is removing. Show a
    // spinner for the ~handful of frames it takes the provider to hydrate.
    if (managedRules == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final managed = _findManaged(managedRules);

    // Row disappeared out from under the selection (Unadopt elsewhere,
    // Reset DB, reconciliation cleaned up an orphan). Clear the
    // selection on the next frame so [RightPane] renders the empty
    // placeholder instead of showing a fabricated ghost row the user
    // can still click. We can't set the provider state mid-build — do it
    // post-frame.
    if (managed == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(selectedRuleProvider)?.exePath == widget.rule.exePath) {
          ref.read(selectedRuleProvider.notifier).state = null;
        }
      });
      return const _EmptyDetail();
    }

    final exclusionState =
        ref.watch(profileExclusionStateProvider)[managed.exePath];
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    // Treat unknown / missing as "not excluded" for the toggle and badge —
    // the user can still flip the switch on, and we'll show a missing-
    // profile note further down if applicable.
    final exclusionEnabled = exclusionState ?? false;
    final stateUnknown = exclusionState == null;
    final isPredef = managed.profileWasPredefined;
    final rowLocked = _busy || bridgeBusy;

    final ruleForFields = widget.rule.copyWith(
      currentValue: exclusionEnabled
          ? AppConstants.captureDisableValue
          : AppConstants.captureEnableValue,
      isPredefined: isPredef,
      profileName: managed.profileName,
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderRow(rule: ruleForFields, excluded: exclusionEnabled),
            const SizedBox(height: 16),
            _FieldsBlock(
              rule: ruleForFields,
              effectiveValue: exclusionEnabled
                  ? AppConstants.captureDisableValue
                  : AppConstants.captureEnableValue,
            ),
            const SizedBox(height: 20),
            _ToggleRow(
              enabled: exclusionEnabled,
              busy: _busy,
              onChanged: rowLocked ? null : (v) => _onToggle(managed, v),
              onUnadopt: rowLocked ? null : () => _confirmUnadopt(managed),
              onMenuAction:
                  rowLocked ? null : (action) => _onMenuAction(managed, action),
              profileIsPredefined: isPredef,
            ),
            const SizedBox(height: 8),
            Text(
              exclusionEnabled
                  ? 'Exclusion is active — NVIDIA capture/Instant Replay '
                      'skip this executable. Toggle off to clear the '
                      'override without losing the profile from your '
                      'watched list.'
                  : 'Exclusion is cleared — NVIDIA capture behaves as it '
                      'normally would for this executable. The profile is '
                      'still watched; toggle on to re-apply.',
              style: theme.textTheme.bodySmall,
            ),
            if (stateUnknown) ...[
              const SizedBox(height: 6),
              Text(
                'Live driver state for this executable hasn\'t been '
                'verified yet. Click Scan Profiles to refresh.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Restart the target application for changes to take full effect.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            AdvancedEditor(rule: ruleForFields, allowEdit: true),
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
  final VoidCallback? onUnadopt;
  final ValueChanged<_RuleMenuAction>? onMenuAction;
  final bool profileIsPredefined;

  const _ToggleRow({
    required this.enabled,
    required this.busy,
    required this.onChanged,
    required this.onUnadopt,
    required this.onMenuAction,
    required this.profileIsPredefined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            size: 18,
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exclusion enabled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  enabled
                      ? 'Currently hidden from capture'
                      : 'Currently visible to capture',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (busy) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          // Shrink the Material switch down a notch and trim its default
          // 48x48 tap-target padding so it sits comfortably inline with
          // the surrounding 40-ish-pixel icon buttons rather than
          // dominating the row.
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: enabled,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onUnadopt,
            icon: const Icon(Icons.bookmark_remove_outlined, size: 16),
            label: const Text('Unadopt'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<_RuleMenuAction>(
            enabled: onMenuAction != null,
            tooltip: 'More actions',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) => onMenuAction?.call(v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _RuleMenuAction.unadopt,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bookmark_remove_outlined),
                  title: Text('Unadopt'),
                  subtitle: Text('Local only — driver unchanged'),
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
  final bool excluded;
  const _HeaderRow({required this.rule, required this.excluded});

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
              // Plan F-46: very long exe paths used to push the
              // `_StatusBadge` off the right edge of the pane because
              // `Text` wraps by default. Clamp to two lines with an
              // ellipsis and expose the full path as a tooltip so
              // users can still read it if they need to.
              Tooltip(
                message: rule.exePath,
                waitDuration: const Duration(milliseconds: 400),
                child: Text(
                  rule.exePath,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        _StatusBadge(excluded: excluded),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool excluded;
  const _StatusBadge({required this.excluded});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = excluded
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final label = excluded ? 'Excluded' : 'Inactive';
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
  final int effectiveValue;
  const _FieldsBlock({required this.rule, required this.effectiveValue});

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
          '0x${effectiveValue.toRadixString(16).toUpperCase().padLeft(8, '0')}',
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
