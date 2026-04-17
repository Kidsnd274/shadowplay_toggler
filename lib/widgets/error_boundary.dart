import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wraps the app's root subtree and swaps any thrown build-time error for
/// a user-friendly fallback pane instead of showing Flutter's red "ErrorWidget".
///
/// Runtime/uncaught errors are captured by `FlutterError.onError` and
/// `PlatformDispatcher.onError` in `main.dart` and surfaced through the
/// notification service; this widget only covers the subtree-build failure
/// case.
///
/// The global [ErrorWidget.builder] is installed once from `main.dart` via
/// [installErrorBoundaryFallback]; this widget only provides the subtree
/// boundary itself so the fallback is rendered inside the Material app.
class ErrorBoundary extends StatelessWidget {
  final Widget child;

  const ErrorBoundary({super.key, required this.child});

  /// Installs the process-wide [ErrorWidget.builder] fallback used by
  /// [ErrorBoundary]. Call exactly once during app bootstrap, before
  /// `runApp`, so the fallback is in place before any frame builds.
  static void installErrorBoundaryFallback() {
    ErrorWidget.builder = _buildFallback;
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }

  static Widget _buildFallback(FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFCF6679), size: 36),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong rendering this screen.',
                style: TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "We've logged the issue. Please try the action again; if "
                'the problem persists, restart the app.',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF3A3A3A)),
                  ),
                  child: SelectableText(
                    details.exceptionAsString(),
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
