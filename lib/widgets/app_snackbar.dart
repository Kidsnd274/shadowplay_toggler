import 'package:flutter/material.dart';

/// Severity buckets for app-wide notifications. Drives both the colour
/// scheme of [AppSnackbar] and the icon used.
enum AppNotificationSeverity { success, error, warning, info }

/// Colour-coded [SnackBar] used for transient notifications throughout the
/// app. Built via [AppSnackbar.build]; callers typically go through
/// [NotificationService] rather than instantiating this directly.
class AppSnackbar {
  AppSnackbar._();

  /// Build a [SnackBar] for the given severity. [actionLabel] / [onAction]
  /// wire up an optional right-aligned action (e.g. "Details", "Retry").
  static SnackBar build(
    BuildContext context, {
    required String message,
    required AppNotificationSeverity severity,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final theme = Theme.of(context);

    final (bg, fg, icon) = switch (severity) {
      AppNotificationSeverity.success => (
          theme.colorScheme.primary.withValues(alpha: 0.95),
          Colors.black,
          Icons.check_circle_outline,
        ),
      AppNotificationSeverity.error => (
          theme.colorScheme.error.withValues(alpha: 0.95),
          Colors.white,
          Icons.error_outline,
        ),
      AppNotificationSeverity.warning => (
          const Color(0xFFFFA000),
          Colors.black,
          Icons.warning_amber_rounded,
        ),
      AppNotificationSeverity.info => (
          const Color(0xFF546E7A),
          Colors.white,
          Icons.info_outline,
        ),
    };

    return SnackBar(
      backgroundColor: bg,
      duration: duration ?? _defaultDurationFor(severity),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      content: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fg, fontSize: 13),
            ),
          ),
        ],
      ),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: fg,
              onPressed: onAction,
            )
          : null,
    );
  }

  static Duration _defaultDurationFor(AppNotificationSeverity severity) {
    switch (severity) {
      case AppNotificationSeverity.error:
        return const Duration(seconds: 6);
      case AppNotificationSeverity.warning:
        return const Duration(seconds: 5);
      case AppNotificationSeverity.success:
      case AppNotificationSeverity.info:
        return const Duration(seconds: 3);
    }
  }
}
