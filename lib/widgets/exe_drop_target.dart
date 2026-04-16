import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/nvapi_state.dart';
import '../providers/nvapi_provider.dart';
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

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (exePaths.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            rejected.isEmpty
                ? 'Nothing to add — drop a .exe file.'
                : 'Only .exe files are supported. '
                    'Ignored: ${rejected.join(', ')}',
          ),
        ),
      );
      return;
    }

    if (rejected.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Ignored non-.exe items: ${rejected.join(', ')}',
          ),
        ),
      );
    }

    if (!_assertNvapiReady()) return;

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
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                result.exclusionAlreadyApplied
                    ? 'Exclusion already applied for ${result.exeName}.'
                    : 'Added exclusion for ${result.exeName}.',
              ),
            ),
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
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
