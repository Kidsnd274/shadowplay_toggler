import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppToolbar extends StatelessWidget {
  final VoidCallback? onScanProfiles;
  final VoidCallback? onAddProgram;
  final VoidCallback? onBackup;
  final VoidCallback? onSettings;

  const AppToolbar({
    super.key,
    this.onScanProfiles,
    this.onAddProgram,
    this.onBackup,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Row(
        children: [
          Text(
            AppConstants.appTitle,
            style: theme.textTheme.titleLarge,
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onScanProfiles,
            icon: const Icon(Icons.radar, size: 18),
            label: const Text('Scan Profiles'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onAddProgram,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Program'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onBackup,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Backup'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
