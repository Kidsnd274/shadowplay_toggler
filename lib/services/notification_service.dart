import 'package:flutter/material.dart';

import '../models/app_exception.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/error_dialog.dart';

/// Centralised entry point for user-facing notifications. Backed by a
/// single process-wide [GlobalKey<ScaffoldMessengerState>] so any layer
/// (services, providers, background isolates via a thin UI shim) can show
/// snackbars without threading a [BuildContext] all the way through.
///
/// The key is installed on [MaterialApp.scaffoldMessengerKey] in
/// `app.dart`; if no key is wired up yet, methods fall back to using the
/// supplied [BuildContext].
class NotificationService {
  NotificationService._();

  /// Global messenger key installed on [MaterialApp]. Callers should use
  /// the top-level helpers below; this field is exposed mostly so the app
  /// shell can hook the key into `MaterialApp.scaffoldMessengerKey`.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static ScaffoldMessengerState? _messenger(BuildContext? context) {
    final state = messengerKey.currentState;
    if (state != null) return state;
    if (context == null) return null;
    return ScaffoldMessenger.maybeOf(context);
  }

  static BuildContext? _context(BuildContext? context) {
    final state = messengerKey.currentState;
    if (state != null && state.context.mounted) return state.context;
    return context;
  }

  static void _show(
    BuildContext? context, {
    required String message,
    required AppNotificationSeverity severity,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = _messenger(context);
    final ctx = _context(context);
    if (messenger == null || ctx == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      AppSnackbar.build(
        ctx,
        message: message,
        severity: severity,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
  }

  static void showSuccess(String message, {BuildContext? context}) {
    _show(
      context,
      message: message,
      severity: AppNotificationSeverity.success,
    );
  }

  static void showError(
    String message, {
    BuildContext? context,
    String? details,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      severity: AppNotificationSeverity.error,
      actionLabel: actionLabel ?? (details != null ? 'Details' : null),
      onAction: onAction ??
          (details != null
              ? () {
                  final ctx = _context(context);
                  if (ctx == null) return;
                  ErrorDialog.show(
                    ctx,
                    title: 'Error details',
                    message: message,
                    technicalDetails: details,
                  );
                }
              : null),
    );
  }

  static void showWarning(String message, {BuildContext? context}) {
    _show(
      context,
      message: message,
      severity: AppNotificationSeverity.warning,
    );
  }

  static void showInfo(
    String message, {
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      severity: AppNotificationSeverity.info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Convenience: show a short info toast telling the user to restart the
  /// target executable so the capture-exclusion change takes effect.
  static void showRestartTargetHint(String exeName, {BuildContext? context}) {
    showInfo(
      'Restart $exeName for changes to take effect.',
      context: context,
    );
  }

  /// Show a user-friendly error message sourced from an [AppException].
  /// Prefers the snackbar path unless [asDialog] is true.
  static Future<void> reportException(
    AppException error, {
    BuildContext? context,
    bool asDialog = false,
    String? title,
  }) async {
    if (asDialog) {
      final ctx = _context(context);
      if (ctx == null) return;
      await ErrorDialog.showForException(
        ctx,
        error,
        title: title,
      );
      return;
    }
    showError(
      error.message,
      context: context,
      details: error.technicalDetails,
    );
  }
}
