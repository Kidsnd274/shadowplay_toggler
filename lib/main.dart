import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/database_provider.dart';
import 'providers/nvapi_provider.dart';
import 'services/log_buffer.dart';
import 'services/notification_service.dart';
import 'widgets/error_boundary.dart';

// The lifecycle listener registers itself with WidgetsBinding.instance in its
// constructor, but we also retain the reference here so the cleanup intent is
// obvious and so nothing accidentally disposes/GCs it. The app runs for the
// entire process lifetime so we never dispose it explicitly.
// ignore: unused_element
AppLifecycleListener? _appLifecycleListener;

void main() {
  // Tee print() into the in-process LogBuffer via a Zone so the Logs
  // viewer can replay everything that would have shown up in the
  // terminal during a `flutter run`. The original print is preserved
  // so console output is unchanged.
  runZonedGuarded(
    _bootstrap,
    (error, stack) {
      LogBuffer.instance.add(LogLevel.error, 'Unhandled zone error: $error');
      LogBuffer.instance.addBlock(LogLevel.error, '$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        LogBuffer.instance.add(LogLevel.info, line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Install the fallback ErrorWidget once, before any frame is built, so
  // subtree build failures never surface Flutter's red default widget.
  ErrorBoundary.installErrorBoundaryFallback();

  _installLogTeeHandlers();
  _installGlobalErrorHandlers();
  LogBuffer.instance.add(LogLevel.info, 'shadowplay_toggler starting up');

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

/// Wires `debugPrint` (the channel Flutter framework noise comes through)
/// into [LogBuffer] so the in-app Logs viewer captures it alongside
/// regular `print()` output. The native bridge already mirrors its
/// messages to stderr, which `runZoned` cannot intercept, so those still
/// require a `flutter run` console — but framework / Dart-side noise is
/// fully covered.
void _installLogTeeHandlers() {
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) {
      LogBuffer.instance.add(LogLevel.info, message);
    }
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };
}

/// Install top-level handlers for framework errors and unhandled async
/// errors. In release builds these surface as a user-friendly snackbar via
/// [NotificationService]; in debug builds they still dump to the console
/// via Flutter's default presenters (red screen) and we skip the snackbar
/// so the developer sees only the single authoritative error surface.
void _installGlobalErrorHandlers() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    LogBuffer.instance.add(LogLevel.error, details.exceptionAsString());
    if (details.stack != null) {
      LogBuffer.instance.addBlock(LogLevel.error, '${details.stack}');
    }
    if (kDebugMode) {
      defaultOnError?.call(details);
      return;
    }
    developer.log(
      details.exceptionAsString(),
      name: 'shadowplay_toggler',
      error: details.exception,
      stackTrace: details.stack,
    );
    NotificationService.showError(
      'An unexpected error occurred.',
      details: details.exceptionAsString(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    LogBuffer.instance.add(LogLevel.error, 'Unhandled async error: $error');
    LogBuffer.instance.addBlock(LogLevel.error, '$stack');
    developer.log(
      'Unhandled async error: $error',
      name: 'shadowplay_toggler',
      error: error,
      stackTrace: stack,
    );
    if (!kDebugMode) {
      NotificationService.showError(
        'An unexpected error occurred.',
        details: '$error',
      );
    }
    return true;
  };
}
