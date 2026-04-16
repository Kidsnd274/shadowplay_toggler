import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/search_provider.dart';
import 'rule_list_tile.dart';

/// "Detected" tab content: lists driver profiles whose capture-exclusion
/// setting was set outside this app.
class DetectedRulesTab extends ConsumerWidget {
  final VoidCallback? onScanProfiles;

  const DetectedRulesTab({super.key, this.onScanProfiles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detected = ref.watch(detectedRulesProvider);
    final rules = ref.watch(filteredDetectedRulesProvider);
    final query = ref.watch(searchProvider);

    if (!detected.hasScanned) {
      return _PreScanState(onScanProfiles: onScanProfiles);
    }

    if (rules.isEmpty) {
      if (query.trim().isNotEmpty) {
        return _NoMatchState(query: query);
      }
      return const _NoDetectedState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rules.length,
      itemBuilder: (context, i) {
        final rule = rules[i];
        return RuleListTile(
          rule: rule,
          sourceBadge: RuleSourceBadge.external,
          statusColor: const Color(0xFFFFB74D),
          statusTooltip: 'External rule — source unknown',
          trailingHint: 'Adopt',
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
              Icons.radar,
              size: 40,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(height: 12),
            Text(
              "Click 'Scan NVIDIA Profiles' to detect existing rules.",
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

class _NoDetectedState extends StatelessWidget {
  const _NoDetectedState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'No external exclusion rules found.',
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
