import 'package:flutter/material.dart';

/// Reusable "are you sure?" dialog. Callers can customise the title,
/// message, button labels, and choose a destructive variant that styles
/// the confirm button in error red.
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  /// Shows the dialog and resolves to `true` on confirm, `false` on cancel
  /// (or on barrier dismiss).
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      // Plan F-47: destructive confirmations (Reset DB, Delete
      // Profile, batch ops) should never be dismissable by a stray
      // click outside the dialog or an accidental Esc — that path
      // returns `null`, which `ConfirmationDialog.show` squashes to
      // `false`, making it *look* like an explicit cancel. For
      // non-destructive prompts, barrier dismiss remains a
      // convenience.
      barrierDismissible: !destructive,
      builder: (_) => ConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: Text(message, style: theme.textTheme.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
