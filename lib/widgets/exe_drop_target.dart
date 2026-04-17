import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/nvapi_state.dart';
import '../providers/nvapi_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../services/notification_service.dart';
import 'add_program_dialog.dart';

/// Wraps [child] in a `DropTarget` that accepts dropped `.exe` files and
/// forwards each to [runAddProgramFlow] as if the user had clicked
/// "Add Program" and pointed to that file.
///
/// Behaviour:
///   * Non-`.exe` items (other extensions, folders) are filtered out.
///   * If nothing usable remains, a snackbar tells the user.
///   * Multiple `.exe` files are processed one after another.
///   * NVAPI must be ready; otherwise a snackbar explains why and the
///     drop is ignored.
///   * While a drag is hovering over the window, a translucent overlay
///     gives the user clear visual confirmation that the drop will be
///     accepted.
///
/// Note (plan F-48): the filter is purely extension-based. A file
/// renamed to `game.exe` that isn't actually a PE binary would still
/// pass this gate — validation happens downstream when
/// [runAddProgramFlow] hands the path to NVAPI. That's considered
/// acceptable for a desktop utility: NVAPI will simply fail to attach
/// a non-executable to a DRS profile and we surface the error. We
/// intentionally don't MIME-sniff / read the PE header here because
/// `.exe` is the de-facto signal on Windows and deeper validation
/// would regress drag-from-Explorer responsiveness.
class ExeDropTarget extends ConsumerStatefulWidget {
  const ExeDropTarget({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ExeDropTarget> createState() => _ExeDropTargetState();
}

class _ExeDropTargetState extends ConsumerState<ExeDropTarget> {
  bool _isHovering = false;
  bool _isProcessing = false;

  void _setHovering(bool value) {
    if (!mounted || _isHovering == value) return;
    setState(() => _isHovering = value);
  }

  Future<void> _onDragDone(DropDoneDetails details) async {
    _setHovering(false);
    if (_isProcessing) return;

    final exePaths = <String>[];
    final rejected = <String>[];
    for (final item in details.files) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (item is DropItemDirectory) {
        rejected.add(p.basename(path));
        continue;
      }
      if (p.extension(path).toLowerCase() == '.exe') {
        exePaths.add(path);
      } else {
        rejected.add(p.basename(path));
      }
    }

    if (exePaths.isEmpty) {
      NotificationService.showWarning(
        rejected.isEmpty
            ? 'Nothing to add — drop a .exe file.'
            : 'Only .exe files are supported. Ignored: ${rejected.join(', ')}',
        context: context,
      );
      return;
    }

    if (rejected.isNotEmpty) {
      NotificationService.showInfo(
        'Ignored non-.exe items: ${rejected.join(', ')}',
        context: context,
      );
    }

    if (!_assertNvapiReady()) return;
    if (!_assertBridgeFree()) return;

    _isProcessing = true;
    try {
      for (final path in exePaths) {
        if (!mounted) break;
        final result = await runAddProgramFlow(
          context,
          ref,
          presetPath: path,
        );
        if (!mounted) break;
        if (result != null && result.success) {
          NotificationService.showSuccess(
            result.exclusionAlreadyApplied
                ? 'Exclusion already applied for ${result.exeName}.'
                : 'Added exclusion for ${result.exeName}.',
            context: context,
          );
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  bool _assertNvapiReady() {
    final state = ref.read(nvapiProvider);
    if (state is NvapiReady) return true;
    final message = switch (state) {
      NvapiInitializing() =>
        'NVAPI is still initialising — try again in a moment.',
      NvapiError(message: final m) => 'NVAPI unavailable: $m',
      _ => 'NVAPI is not ready yet.',
    };
    NotificationService.showWarning(message, context: context);
    return false;
  }

  /// Refuse drops while a scan or startup reconciliation is running —
  /// the bridge DLL session is single-writer. See plan F-16.
  bool _assertBridgeFree() {
    if (!ref.read(bridgeBusyProvider)) return true;
    final reconciling = ref.read(isReconcilingProvider);
    final msg = reconciling
        ? 'Startup reconciliation is still running — try again in a moment.'
        : 'A scan is in progress — try again in a moment.';
    NotificationService.showInfo(msg, context: context);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: _onDragDone,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_isHovering)
            Positioned.fill(
              child: IgnorePointer(
                child: _DropOverlay(),
              ),
            ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent, width: 3),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_for_offline_outlined,
                  size: 28, color: accent),
              const SizedBox(width: 12),
              Text(
                'Drop .exe to add an exclusion',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
