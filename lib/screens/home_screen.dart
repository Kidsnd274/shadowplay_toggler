import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nvapi_state.dart';
import '../providers/nvapi_provider.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/left_pane.dart';
import '../widgets/right_pane.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(nvapiProvider.notifier).initialize();
    });
  }

  void _showNotImplemented(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — not implemented yet'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onScanProfiles() => _showNotImplemented('Scan Profiles');

  @override
  Widget build(BuildContext context) {
    final nvapiState = ref.watch(nvapiProvider);

    return Scaffold(
      body: Column(
        children: [
          AppToolbar(
            onScanProfiles: _onScanProfiles,
            onAddProgram: () => _showNotImplemented('Add Program'),
            onBackup: () => _showNotImplemented('Backup'),
            onSettings: () => _showNotImplemented('Settings'),
          ),
          if (nvapiState is NvapiError)
            _NvapiBanner(message: nvapiState.message),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: 1,
                  child: LeftPane(onScanProfiles: _onScanProfiles),
                ),
                const Flexible(flex: 2, child: RightPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NvapiBanner extends StatelessWidget {
  final String message;
  const _NvapiBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.error.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'NVAPI Error: $message',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
