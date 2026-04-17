import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reconciliation_result.dart';
import '../providers/reconciliation_provider.dart';
import '../providers/selected_tab_provider.dart';

/// Passive notice that appears when the most recent reconciliation
/// detected an NVIDIA driver change (the DRS profile hash differed from
/// the one stored at the previous launch).
///
/// We deliberately do *not* show this banner for ordinary drift /
/// orphan / "out of sync" cases. The status dot in the Managed list
/// already communicates per-profile state, and the actions on
/// individual profiles cover the recovery path. A banner is only
/// warranted when the user needs a heads-up that something *outside*
/// the app changed underfoot.
class ReconciliationBanner extends ConsumerStatefulWidget {
  const ReconciliationBanner({super.key});

  @override
  ConsumerState<ReconciliationBanner> createState() =>
      _ReconciliationBannerState();
}

class _ReconciliationBannerState extends ConsumerState<ReconciliationBanner> {
  // Banner dismissal is UI-local state. Storing it on the provider
  // (the old approach — `state = null` on dismiss) discarded the whole
  // reconciliation result and fought any other consumer that wanted
  // to read `drsResetDetected`, `warnings`, `duration`, etc. Plan F-27.
  bool _dismissed = false;
  ReconciliationResult? _lastSeen;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(lastReconciliationProvider);

    // A new reconciliation run should always resurface the banner —
    // the previous dismissal was about an older event.
    if (!identical(result, _lastSeen)) {
      _lastSeen = result;
      _dismissed = false;
    }

    if (result == null || !result.drsResetDetected || _dismissed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.error.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.refresh, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'NVIDIA driver change detected. Open the Managed Profiles '
              'tab to review the current state of each watched profile '
              'and re-enable the exclusions you want.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: _goToManaged,
            child: const Text('Open Managed Profiles'),
          ),
          TextButton(
            onPressed: _dismiss,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _goToManaged() {
    ref.read(selectedTabProvider.notifier).state = LeftPaneTab.managed;
    _dismiss();
  }

  void _dismiss() {
    setState(() => _dismissed = true);
  }
}
