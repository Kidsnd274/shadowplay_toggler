import 'package:flutter/material.dart';

class LeftPane extends StatelessWidget {
  const LeftPane({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Center(
        child: Text(
          'Left Pane',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
