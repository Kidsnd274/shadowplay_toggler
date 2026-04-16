import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/nvidia_defaults_provider.dart';
import '../providers/search_provider.dart';
import 'rule_list_tile.dart';

/// "NVIDIA Defaults" tab content: predefined profiles that ship with the
/// driver and carry the capture-exclusion setting. Read-only.
class NvidiaDefaultsTab extends ConsumerWidget {
  final VoidCallback? onScanProfiles;

  const NvidiaDefaultsTab({super.key, this.onScanProfiles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(nvidiaDefaultsProvider);
    final rules = ref.watch(filteredNvidiaDefaultsProvider);
    final query = ref.watch(searchProvider);

    if (!defaults.hasScanned) {
      return _PreScanState(onScanProfiles: onScanProfiles);
    }

    if (rules.isEmpty) {
      if (query.trim().isNotEmpty) {
        return _NoMatchState(query: query);
      }
      return const _NoDefaultsState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rules.length,
      itemBuilder: (context, i) {
        final rule = rules[i];
        return RuleListTile(
          rule: rule,
          sourceBadge: RuleSourceBadge.nvidiaDefault,
          statusColor: Colors.blueGrey.shade300,
          statusTooltip: 'Read-only NVIDIA default',
          dimmed: true,
        );
      },
    );
  }
}

class _PreScanState extends StatelessWidget {
  final VoidCallback? onScanProfiles;
  const _PreScanState({this.onScanProfiles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.factory_outlined,
              size: 40,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(height: 12),
            Text(
              "Click 'Scan NVIDIA Profiles' to view NVIDIA default profiles.",
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (onScanProfiles != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onScanProfiles,
                icon: const Icon(Icons.radar, size: 16),
                label: const Text('Scan Profiles'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoDefaultsState extends StatelessWidget {
  const _NoDefaultsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'No NVIDIA default profiles with this setting were found.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  final String query;
  const _NoMatchState({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          "No rules matching '$query'",
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
