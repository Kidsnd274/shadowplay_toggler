import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/batch_result.dart';
import '../models/reconciliation_result.dart';
import '../providers/batch_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/selected_tab_provider.dart';
import '../services/notification_service.dart';
import 'confirmation_dialog.dart';

/// Banner shown above the main content when the latest reconciliation
/// surfaced an issue (DRS reset, drift, or orphaned rules). The banner
/// has a built-in "Dismiss" action that clears [lastReconciliationProvider]
/// locally without persisting — the next reconciliation pass will
/// recompute state.
class ReconciliationBanner extends ConsumerStatefulWidget {
  const ReconciliationBanner({super.key});

  @override
  ConsumerState<ReconciliationBanner> createState() =>
      _ReconciliationBannerState();
}

class _ReconciliationBannerState extends ConsumerState<ReconciliationBanner> {
  bool _busy = false;

  Future<void> _reapplyAll(ReconciliationResult result) async {
    final managed = ref.read(managedRulesProvider).valueOrNull ?? const [];
    if (managed.isEmpty) return;

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Re-apply ${managed.length} managed rules?',
      message:
          'NVIDIA driver state looks like it was reset. Re-apply every rule '
          'in the Managed list to restore your exclusions.',
      confirmLabel: 'Re-apply All',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(batchServiceProvider);
      final batch = await service.batchEnable(managed);
      if (!mounted) return;
      _reportBatch(batch);
      await ref.read(managedRulesProvider.notifier).refresh();
      ref.read(lastReconciliationProvider.notifier).state = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportBatch(BatchResult batch) {
    if (!batch.hasFailures) {
      NotificationService.showSuccess(
        'Re-applied ${batch.succeeded} of ${batch.total} rules.',
      );
    } else {
      NotificationService.showError(
        'Re-applied ${batch.succeeded} of ${batch.total}. '
        '${batch.failed} failed.',
        details: batch.errors.join('\n'),
      );
    }
  }

  void _openManagedTab() {
    ref.read(selectedTabProvider.notifier).state = LeftPaneTab.managed;
    ref.read(lastReconciliationProvider.notifier).state = null;
  }

  void _dismiss() {
    ref.read(lastReconciliationProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(lastReconciliationProvider);
    if (result == null || !result.hasAnyIssue) return const SizedBox.shrink();

    if (result.drsResetDetected) {
      return _BannerShell(
        tone: _Tone.danger,
        icon: Icons.refresh,
        message: 'Driver change detected — ${result.rulesNeedingReapply} '
            'managed rules need to be re-applied.',
        actions: [
          FilledButton(
            onPressed: _busy ? null : () => _reapplyAll(result),
            child: const Text('Re-apply All'),
          ),
          TextButton(
            onPressed: _busy ? null : _openManagedTab,
            child: const Text('Review'),
          ),
        ],
        busy: _busy,
      );
    }

    final messages = <String>[];
    if (result.rulesDrifted > 0) {
      messages.add(
        '${result.rulesDrifted} managed rule'
        '${result.rulesDrifted == 1 ? '' : 's'} changed in the driver.',
      );
    }
    if (result.rulesOrphaned > 0) {
      messages.add(
        '${result.rulesOrphaned} managed rule'
        '${result.rulesOrphaned == 1 ? '' : 's'} could not be found in the '
        'driver.',
      );
    }

    return _BannerShell(
      tone: _Tone.warning,
      icon: Icons.info_outline,
      message: messages.join('  '),
      actions: [
        TextButton(onPressed: _openManagedTab, child: const Text('Review')),
        TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
      ],
      busy: _busy,
    );
  }
}

enum _Tone { warning, danger }

class _BannerShell extends StatelessWidget {
  final _Tone tone;
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final bool busy;

  const _BannerShell({
    required this.tone,
    required this.icon,
    required this.message,
    required this.actions,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (tone) {
      _Tone.danger => (
          theme.colorScheme.error.withValues(alpha: 0.15),
          theme.colorScheme.error,
        ),
      _Tone.warning => (
          const Color(0xFFFFA000).withValues(alpha: 0.15),
          const Color(0xFFFFB74D),
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bg,
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
          ...actions,
          if (busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
