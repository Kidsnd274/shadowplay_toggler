import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exclusion_rule.dart';
import '../providers/adopt_rule_provider.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../services/notification_service.dart';
import 'confirmation_dialog.dart';

/// Shared adopt-single-rule flow used by [AdoptRuleButton] and by inline
/// "Adopt" actions in the Detected tab list. Shows a confirmation dialog,
/// invokes [AdoptRuleService], posts notifications, and on success moves
/// the rule from the Detected list into the Managed list (re-selecting it
/// in its new managed form so the detail pane updates).
///
/// Returns true if the rule was adopted (or was already managed). Returns
/// false if the user cancelled or adoption failed.
Future<bool> adoptRuleInteractive(
  BuildContext context,
  WidgetRef ref,
  ExclusionRule rule,
) async {
  final confirmed = await ConfirmationDialog.show(
    context,
    title: 'Adopt exclusion rule for ${rule.exeName}?',
    message:
        'This rule was created externally. Adopting it lets you manage it '
        'from this app — the NVIDIA driver value is not changed.',
    confirmLabel: 'Adopt',
  );
  if (!confirmed) return false;

  final service = ref.read(adoptRuleServiceProvider);
  final result = await service.adoptRule(rule);

  if (!result.success) {
    NotificationService.showError(
      result.errorMessage ?? 'Failed to adopt rule.',
    );
    return false;
  }
  if (result.alreadyManaged) {
    NotificationService.showInfo(
      '${rule.exeName} is already in your Managed list.',
    );
  } else {
    NotificationService.showSuccess('Adopted ${rule.exeName}.');
    if (result.valueChangedSinceScan) {
      NotificationService.showWarning(
        'Setting value had changed since the last scan — adopted the live '
        'value instead.',
      );
    }
  }

  final detected = ref.read(detectedRulesProvider);
  final remaining = detected.rules
      .where((r) => r.exePath != rule.exePath)
      .toList(growable: false);
  ref.read(detectedRulesProvider.notifier).setRules(remaining);

  await ref.read(managedRulesProvider.notifier).refresh();

  // Re-select the rule in its new "managed" form so the detail pane
  // updates to show the editable controls.
  ref.read(selectedRuleProvider.notifier).state = rule.copyWith(
    sourceType: 'managed',
    isManaged: true,
  );

  return true;
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _onAdopt,
              icon: const Icon(Icons.bookmark_add_outlined, size: 16),
              label: const Text('Adopt this rule'),
            ),
            if (_busy) ...[
              const SizedBox(width: 12),
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Take control of this rule. It will appear in your Managed list.',
          style: theme.textTheme.bodySmall,
        ),
      ],
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
    final rules = ref.read(detectedRulesProvider).rules;
    if (rules.isEmpty) return;

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Adopt all detected rules?',
      message:
          'Move all ${rules.length} detected exclusion rules into your '
          'Managed list. NVIDIA driver values are not changed.',
      confirmLabel: 'Adopt All',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(adoptRuleServiceProvider);
      final result = await service.adoptAll(rules);
      if (!mounted) return;

      // Refresh state regardless of individual failures.
      ref.read(detectedRulesProvider.notifier).clear();
      await ref.read(managedRulesProvider.notifier).refresh();

      if (result.failed == 0) {
        NotificationService.showSuccess(
          result.adopted == 0
              ? 'All ${result.total} rules were already managed.'
              : 'Adopted ${result.adopted} rule'
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _onAdoptAll,
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
