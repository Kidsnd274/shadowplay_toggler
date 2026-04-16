import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/database_provider.dart';
import 'providers/nvapi_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  await container.read(databaseServiceProvider).initialize();

  AppLifecycleListener(onExitRequested: () async {
    container.read(nvapiProvider.notifier).shutdown();
    await container.read(databaseServiceProvider).close();
    return AppExitResponse.exit;
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ShadowPlayTogglerApp(),
    ),
  );
}
