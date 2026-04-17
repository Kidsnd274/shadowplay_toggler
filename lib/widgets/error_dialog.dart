import 'package:flutter/material.dart';

import '../models/app_exception.dart';

/// Modal dialog used for serious, actionable errors that warrant the user's
/// attention. Less scary errors should still go through a snackbar via
/// [NotificationService].
class ErrorDialog extends StatefulWidget {
  final String title;
  final String message;
  final String? technicalDetails;
  final String confirmLabel;
  final String? retryLabel;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.technicalDetails,
    this.confirmLabel = 'OK',
    this.retryLabel,
  });

  /// Helper that derives dialog contents from an [AppException].
  static Future<ErrorDialogResult?> showForException(
    BuildContext context,
    AppException error, {
    String? title,
    String? retryLabel,
  }) {
    return show(
      context,
      title: title ?? 'Something went wrong',
      message: error.message,
      technicalDetails: error.technicalDetails,
      retryLabel: retryLabel,
    );
  }

  static Future<ErrorDialogResult?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? technicalDetails,
    String? retryLabel,
    String confirmLabel = 'OK',
  }) {
    return showDialog<ErrorDialogResult>(
      context: context,
      builder: (_) => ErrorDialog(
        title: title,
        message: message,
        technicalDetails: technicalDetails,
        confirmLabel: confirmLabel,
        retryLabel: retryLabel,
      ),
    );
  }

  @override
  State<ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<ErrorDialog> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.title)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: theme.textTheme.bodyMedium),
            if (widget.technicalDetails != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(
                  () => _detailsExpanded = !_detailsExpanded,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _detailsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _detailsExpanded ? 'Hide details' : 'Show details',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_detailsExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    widget.technicalDetails!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (widget.retryLabel != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(ErrorDialogResult.retry),
            child: Text(widget.retryLabel!),
          ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ErrorDialogResult.dismissed),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

enum ErrorDialogResult { dismissed, retry }
