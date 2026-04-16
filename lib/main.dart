import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/nvapi_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  AppLifecycleListener(onExitRequested: () async {
    container.read(nvapiProvider.notifier).shutdown();
    return AppExitResponse.exit;
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ShadowPlayTogglerApp(),
    ),
  );
}
