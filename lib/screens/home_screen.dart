import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../providers/nvapi_provider.dart';
import '../models/nvapi_state.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _stateLabel(NvapiState state) => switch (state) {
        NvapiUninitialized() => 'Uninitialized',
        NvapiInitializing() => 'Initializing…',
        NvapiReady() => 'Ready',
        NvapiError(message: final msg) => 'Error: $msg',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nvapiState = ref.watch(nvapiProvider);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppConstants.appTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'NVAPI: ${_stateLabel(nvapiState)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
