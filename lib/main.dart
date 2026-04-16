import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/database_provider.dart';
import 'providers/nvapi_provider.dart';

// The lifecycle listener registers itself with WidgetsBinding.instance in its
// constructor, but we also retain the reference here so the cleanup intent is
// obvious and so nothing accidentally disposes/GCs it. The app runs for the
// entire process lifetime so we never dispose it explicitly.
// ignore: unused_element
AppLifecycleListener? _appLifecycleListener;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  await container.read(databaseServiceProvider).initialize();

  _appLifecycleListener = AppLifecycleListener(
    onExitRequested: () async {
      container.read(nvapiProvider.notifier).shutdown();
      await container.read(databaseServiceProvider).close();
      return AppExitResponse.exit;
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ShadowPlayTogglerApp(),
    ),
  );
}
