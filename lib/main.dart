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

  // Plan F-51: wire native bridge_log() output into the LogBuffer
  // before the first DLL call, so bridge_initialize()'s own log lines
  // (e.g. "NvAPI_Initialize -> 0") end up on the Logs screen rather
  // than only in `flutter run`'s stderr. Reading bridgeFfiProvider
  // here eagerly loads the DLL, which is exactly what we want — the
  // first subsequent NVAPI call (via HomeScreen.initState) will reuse
  // the same BridgeFfi instance from the provider container.
  _installBridgeLogForwarding(container);

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
/// regular `print()` output. Plan F-51 additionally routes the native
/// bridge's `bridge_log` output through [_installBridgeLogForwarding],
/// so the Logs screen now covers framework + Dart-side *and* native
/// NVAPI noise without needing a `flutter run` console.
void _installLogTeeHandlers() {
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) {
      LogBuffer.instance.add(LogLevel.info, message);
    }
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };
}

/// Plan F-51: forward every `bridge_log(…)` call from the native DLL
/// into [LogBuffer] so it's visible on the Logs screen.
///
/// The callback is registered via a [NativeCallable.listener], which:
///   * is safe to invoke from NVAPI's internal worker threads, and
///   * is shared with the scan worker isolate because the DLL is
///     loaded once per process — `LoadLibrary`/FFI returns the same
///     module handle, so the global callback pointer stored by
///     `bridge_set_log_callback` is visible to every call into the
///     DLL regardless of which isolate made it.
///
/// We do a tiny bit of severity inference: the native side only emits
/// one category of warning today (`"  WARNING: scan exceeded 2000 ms"`),
/// so we bump those to [LogLevel.warn] and leave everything else at
/// info. Errors out of the DLL arrive as structured JSON responses,
/// which the Dart callers already translate into their own log
/// entries via [NvapiBridgeException], so we don't try to re-parse
/// them here.
void _installBridgeLogForwarding(ProviderContainer container) {
  final bridge = container.read(bridgeFfiProvider);
  bridge.setLogCallback((line) {
    final level = line.contains('WARNING') ? LogLevel.warn : LogLevel.info;
    LogBuffer.instance.add(level, line);
  });
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
