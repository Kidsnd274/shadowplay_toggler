import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exclusion_rule.dart';
import '../providers/adopt_rule_provider.dart';
import '../providers/destructive_mutation.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/profile_exclusion_state_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../services/notification_service.dart';
import 'confirmation_dialog.dart';

/// Backstop check for actions that enter the native bridge. Returns
/// false and emits a snackbar if a scan or startup reconciliation pass
/// is running — we must not let a second thread race the shared
/// session (see plan F-16). Buttons should already gate on
/// [bridgeBusyProvider] in their `build`, but dialogs/keyboard paths
/// can still invoke these flows mid-scan, so double-check here.
bool _assertBridgeFree(BuildContext context, WidgetRef ref) {
  if (!ref.read(bridgeBusyProvider)) return true;
  final reconciling = ref.read(isReconcilingProvider);
  final msg = reconciling
      ? 'Startup reconciliation is still running — try again in a moment.'
      : 'A scan is in progress — try again in a moment.';
  NotificationService.showInfo(msg, context: context);
  return false;
}

/// Shared "watch this profile" flow used by [AdoptRuleButton] and by
/// inline "Adopt" actions in the Detected tab list. Adoption is purely
/// local — the NVIDIA driver value is not touched. The row simply moves
/// from the Detected list into the Managed list.
///
/// Returns true if the profile is now in the Managed list (either we
/// added it now or it was already there). Returns false if the user
/// cancelled or adoption failed.
Future<bool> adoptRuleInteractive(
  BuildContext context,
  WidgetRef ref,
  ExclusionRule rule, {
  bool skipConfirmation = false,
}) async {
  // Adopt still calls `NvapiService.findApplication` to re-resolve the
  // live profile name, so gate it like any other bridge-touching flow.
  if (!_assertBridgeFree(context, ref)) return false;

  if (!skipConfirmation) {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Watch profile for ${rule.exeName}?',
      message:
          'Add this profile to your Managed list. The NVIDIA driver is '
          'not touched — the exclusion stays exactly as it is. You can '
          'unadopt at any time without affecting the driver.',
      confirmLabel: 'Adopt',
    );
    if (!confirmed) return false;
  }

  final service = ref.read(adoptRuleServiceProvider);
  final result = await service.adoptRule(rule);

  if (!result.success) {
    NotificationService.showError(
      result.errorMessage ?? 'Failed to adopt profile.',
    );
    return false;
  }
  if (result.alreadyManaged) {
    NotificationService.showInfo(
      '${rule.exeName} is already in your Managed list.',
    );
  } else {
    NotificationService.showSuccess('Adopted ${rule.exeName}.');
  }

  await _afterAdoptHousekeeping(ref, rule);
  return true;
}

/// "Adopt + Add Exclusion" flow. Watches the profile *and* applies the
/// capture-exclusion in a single step. Used by the inline "Add
/// Exclusion" button in the Detected tab.
Future<bool> addExclusionInteractive(
  BuildContext context,
  WidgetRef ref,
  ExclusionRule rule,
) async {
  if (!_assertBridgeFree(context, ref)) return false;

  final confirmed = await ConfirmationDialog.show(
    context,
    title: 'Add exclusion for ${rule.exeName}?',
    message:
        'Adopt this profile into the Managed list and turn the '
        'capture-exclusion on. NVIDIA capture / Instant Replay will skip '
        'this executable. You can toggle it off later without losing the '
        'profile from your Managed list.',
    confirmLabel: 'Add Exclusion',
  );
  if (!confirmed) return false;

  final service = ref.read(adoptRuleServiceProvider);
  final result = await service.adoptAndAddExclusion(rule);

  if (!result.success) {
    NotificationService.showError(
      result.errorMessage ?? 'Failed to add exclusion.',
    );
    return false;
  }

  if (result.alreadyManaged) {
    NotificationService.showInfo(
      '${rule.exeName} is already in your Managed list.',
    );
  } else {
    NotificationService.showSuccess('Added exclusion for ${rule.exeName}.');
    NotificationService.showRestartTargetHint(rule.exeName);
  }

  await _afterAdoptHousekeeping(ref, rule, exclusionEnabled: true);
  return true;
}

/// Shared housekeeping after a successful adopt/add-exclusion: refresh
/// providers, update the live state map, and remove the rule from the
/// Detected list.
Future<void> _afterAdoptHousekeeping(
  WidgetRef ref,
  ExclusionRule rule, {
  bool? exclusionEnabled,
}) async {
  final detected = ref.read(detectedRulesProvider);
  final remaining = detected.rules
      .where((r) => r.exePath != rule.exePath)
      .toList(growable: false);
  ref.read(detectedRulesProvider.notifier).setRules(remaining);

  await ref.read(managedRulesProvider.notifier).refresh();

  // Update the single source of truth for exclusion state. If we just
  // applied the exclusion, we already know the value; otherwise do a
  // best-effort live query so the dot reflects reality immediately.
  final stateNotifier = ref.read(profileExclusionStateProvider.notifier);
  if (exclusionEnabled != null) {
    stateNotifier.setForExe(rule.exePath, exclusionEnabled);
  } else {
    await stateNotifier.refreshExe(rule.exePath);
  }

  // Re-select the rule in its new "managed" form so the detail pane
  // updates to show the editable controls.
  if (ref.read(selectedRuleProvider) == rule) {
    ref.read(selectedRuleProvider.notifier).state = rule.copyWith(
      source: ExclusionSource.managed,
      isManaged: true,
    );
  }
}

/// "Adopt this rule" button shown in the detail view for detected/external
/// exclusion rules. Confirms with the user, calls [AdoptRuleService], and
/// on success moves the rule from the Detected list to the Managed list.
class AdoptRuleButton extends ConsumerStatefulWidget {
  final ExclusionRule rule;

  const AdoptRuleButton({super.key, required this.rule});

  @override
  ConsumerState<AdoptRuleButton> createState() => _AdoptRuleButtonState();
}

class _AdoptRuleButtonState extends ConsumerState<AdoptRuleButton> {
  bool _busy = false;

  Future<void> _onAdopt() async {
    setState(() => _busy = true);
    try {
      await adoptRuleInteractive(context, ref, widget.rule);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return OutlinedButton.icon(
      onPressed: (_busy || bridgeBusy) ? null : _onAdopt,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.bookmark_add_outlined, size: 16),
      label: const Text('Adopt'),
    );
  }
}

/// Compact action chip used inline on each row of the Detected tab.
/// Two flavours via [filled]:
///   * `false` (Adopt) — neutral outlined chip, watch-only.
///   * `true`  (Add Exclusion) — primary-filled chip, adopts AND turns
///     the exclusion on in one step.
class _DetectedRowChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool busy;
  final bool filled;
  final VoidCallback? onPressed;

  const _DetectedRowChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.busy,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final bg = filled ? primary.withValues(alpha: 0.18) : Colors.transparent;
    final fg = filled
        ? primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.85);
    final side = filled
        ? BorderSide.none
        : BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: side),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation<Color>(fg),
                        ),
                      )
                    : Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Adopt" chip — local watch only, no driver mutation.
class AdoptInlineButton extends ConsumerStatefulWidget {
  final ExclusionRule rule;
  const AdoptInlineButton({super.key, required this.rule});

  @override
  ConsumerState<AdoptInlineButton> createState() => _AdoptInlineButtonState();
}

class _AdoptInlineButtonState extends ConsumerState<AdoptInlineButton> {
  bool _busy = false;

  Future<void> _onAdopt() async {
    setState(() => _busy = true);
    try {
      await adoptRuleInteractive(context, ref, widget.rule);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return _DetectedRowChip(
      icon: Icons.bookmark_add_outlined,
      label: 'Adopt',
      tooltip: bridgeBusy
          ? 'Wait for the current scan to finish'
          : 'Watch this profile (driver unchanged)',
      busy: _busy,
      filled: false,
      onPressed: bridgeBusy ? null : _onAdopt,
    );
  }
}

/// "Add Exclusion" chip — adopt + apply the capture-exclusion in one
/// step. Use when the user is sure they want this exe excluded right
/// now.
class AddExclusionInlineButton extends ConsumerStatefulWidget {
  final ExclusionRule rule;
  const AddExclusionInlineButton({super.key, required this.rule});

  @override
  ConsumerState<AddExclusionInlineButton> createState() =>
      _AddExclusionInlineButtonState();
}

class _AddExclusionInlineButtonState
    extends ConsumerState<AddExclusionInlineButton> {
  bool _busy = false;

  Future<void> _onAdd() async {
    setState(() => _busy = true);
    try {
      await addExclusionInteractive(context, ref, widget.rule);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return _DetectedRowChip(
      icon: Icons.visibility_off_outlined,
      label: 'Exclude',
      tooltip: bridgeBusy
          ? 'Wait for the current scan to finish'
          : 'Adopt this profile and turn the exclusion on',
      busy: _busy,
      filled: true,
      onPressed: bridgeBusy ? null : _onAdd,
    );
  }
}

/// "Adopt All" button shown above the Detected rules list. Visible when
/// there are any detected rules. Confirms with the user and kicks off a
/// batch adopt via [AdoptRuleService.adoptAll].
class AdoptAllButton extends ConsumerStatefulWidget {
  const AdoptAllButton({super.key});

  @override
  ConsumerState<AdoptAllButton> createState() => _AdoptAllButtonState();
}

class _AdoptAllButtonState extends ConsumerState<AdoptAllButton> {
  bool _busy = false;

  Future<void> _onAdoptAll() async {
    if (!_assertBridgeFree(context, ref)) return;

    final rules = ref.read(detectedRulesProvider).rules;
    if (rules.isEmpty) return;

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Adopt all detected profiles?',
      message:
          'Move all ${rules.length} detected exclusion profiles into your '
          'Managed list. NVIDIA driver values are not changed.',
      confirmLabel: 'Adopt All',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(adoptRuleServiceProvider);
      final result = await service.adoptAll(rules);
      if (!mounted) return;

      // Refresh state regardless of individual failures. Every detected
      // rule either moved into Managed or stayed failed; both outcomes
      // invalidate the currently-selected rule pointer (it's still an
      // `external` ExclusionRule), the last scan snapshot (its detected
      // bucket and managedLiveValues maps are now wrong), and the
      // reconciliation banner (its numbers referenced the old buckets).
      // Adopt keeps NVIDIA defaults and the live-exclusion map intact
      // (both remain valid — managed rows just got *added*, not
      // removed).
      await afterDestructiveMutation(ref);

      if (result.failed == 0) {
        NotificationService.showSuccess(
          result.adopted == 0
              ? 'All ${result.total} profiles were already managed.'
              : 'Adopted ${result.adopted} profile'
                  '${result.adopted == 1 ? '' : 's'}.',
        );
      } else {
        NotificationService.showError(
          'Adopted ${result.adopted} of ${result.total}. '
          '${result.failed} failed.',
          details: result.errors.join('\n'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detected = ref.watch(detectedRulesProvider);
    if (detected.rules.isEmpty) return const SizedBox.shrink();
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: (_busy || bridgeBusy) ? null : _onAdoptAll,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bookmarks_outlined, size: 16),
          label: Text('Adopt All (${detected.rules.length})'),
        ),
      ),
    );
  }
}
