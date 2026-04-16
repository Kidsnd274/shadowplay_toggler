import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/batch_result.dart';
import '../models/managed_rule.dart';
import '../providers/batch_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/multi_select_provider.dart';
import '../services/notification_service.dart';
import 'confirmation_dialog.dart';

/// Bottom action bar for multi-select mode on the Managed list.
///
/// Appears above the left-pane tabs when [multiSelectModeProvider] is on.
/// Shows the current selection count and [Enable All] / [Disable All] /
/// [Cancel] actions.
class BatchActionBar extends ConsumerStatefulWidget {
  const BatchActionBar({super.key});

  @override
  ConsumerState<BatchActionBar> createState() => _BatchActionBarState();
}

class _BatchActionBarState extends ConsumerState<BatchActionBar> {
  bool _busy = false;

  Future<void> _runBatch({required bool enable}) async {
    final ids = ref.read(selectedRuleIdsProvider);
    final all = ref.read(managedRulesProvider).valueOrNull ?? const [];
    final selected = all.where((r) => r.id != null && ids.contains(r.id)).toList();
    if (selected.isEmpty) {
      NotificationService.showInfo('No rules selected.');
      return;
    }

    final verb = enable ? 'Enable' : 'Disable';
    final confirmed = await ConfirmationDialog.show(
      context,
      title: '$verb ${selected.length} rule${selected.length == 1 ? '' : 's'}?',
      message: enable
          ? 'Apply the capture-exclusion setting to the selected profiles.'
          : 'Clear the capture-exclusion setting on the selected profiles. '
              'Their managed rows stay so you can re-enable later.',
      confirmLabel: verb,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(batchServiceProvider);
      final result = enable
          ? await service.batchEnable(selected)
          : await service.batchDisable(selected);
      if (!mounted) return;
      _reportResult(result, verb: verb);
      await ref.read(managedRulesProvider.notifier).refresh();
      exitMultiSelect(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportResult(BatchResult result, {required String verb}) {
    if (!result.hasFailures) {
      NotificationService.showSuccess(
        '${verb}d ${result.succeeded} of ${result.total} rules.',
      );
    } else {
      NotificationService.showError(
        '${verb}d ${result.succeeded} of ${result.total}. '
        '${result.failed} failed.',
        details: result.errors.join('\n'),
      );
    }
  }

  Future<void> _selectAll() async {
    final all = ref.read(managedRulesProvider).valueOrNull ?? const [];
    final ids = all
        .map((r) => r.id)
        .whereType<int>()
        .toSet();
    ref.read(selectedRuleIdsProvider.notifier).state = ids;
  }

  void _clearSelection() {
    ref.read(selectedRuleIdsProvider.notifier).state = const {};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = ref.watch(selectedRuleIdsProvider);
    final all = ref.watch(managedRulesProvider).valueOrNull ?? const <ManagedRule>[];
    final count = ids.length;
    final allSelected = count > 0 && count == all.length;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              '$count selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : (allSelected ? _clearSelection : _selectAll),
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_busy || count == 0)
                  ? null
                  : () => _runBatch(enable: true),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Enable'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: (_busy || count == 0)
                  ? null
                  : () => _runBatch(enable: false),
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              label: const Text('Disable'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : () => exitMultiSelect(ref),
              child: const Text('Cancel'),
            ),
            if (_busy) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
