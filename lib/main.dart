import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/database_provider.dart';
import 'providers/nvapi_provider.dart';
import 'services/notification_service.dart';

// The lifecycle listener registers itself with WidgetsBinding.instance in its
// constructor, but we also retain the reference here so the cleanup intent is
// obvious and so nothing accidentally disposes/GCs it. The app runs for the
// entire process lifetime so we never dispose it explicitly.
// ignore: unused_element
AppLifecycleListener? _appLifecycleListener;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _installGlobalErrorHandlers();

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

/// Install top-level handlers for framework errors and unhandled async
/// errors. In release builds these surface as a user-friendly snackbar via
/// [NotificationService]; in debug builds they still dump to the console
/// via Flutter's default presenters.
void _installGlobalErrorHandlers() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kDebugMode) {
      defaultOnError?.call(details);
    } else {
      developer.log(
        details.exceptionAsString(),
        name: 'shadowplay_toggler',
        error: details.exception,
        stackTrace: details.stack,
      );
    }
    NotificationService.showError(
      'An unexpected error occurred.',
      details: details.exceptionAsString(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Unhandled async error: $error',
      name: 'shadowplay_toggler',
      error: error,
      stackTrace: stack,
    );
    NotificationService.showError(
      'An unexpected error occurred.',
      details: '$error',
    );
    return true;
  };
}
