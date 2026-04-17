import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/log_buffer.dart';
import '../services/notification_service.dart';

/// Read-only viewer for the in-process [LogBuffer]. Live-tails new
/// entries by default and offers Copy All / Clear / scroll-to-bottom
/// controls so the user can grab a chunk of context for a bug report.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

/// Coalescing window for live-tail repaints. Chatty code paths (a
/// scan firing 50 native lines in quick succession) used to call
/// `setState` once per entry, which meant rebuilding the Logs screen
/// dozens of times a second. A 100ms throttle collapses those bursts
/// into a single repaint without making the UI feel stale.
///
/// Plan F-25.
const Duration _kLogTailThrottle = Duration(milliseconds: 100);

class _LogsScreenState extends State<LogsScreen> {
  late List<LogEntry> _entries;
  StreamSubscription<LogEntry>? _sub;
  StreamSubscription<void>? _clearSub;
  Timer? _pendingRefresh;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    _entries = LogBuffer.instance.snapshot();
    _sub = LogBuffer.instance.stream.listen((_) => _scheduleRefresh());
    _clearSub = LogBuffer.instance.clears.listen((_) {
      if (!mounted) return;
      // Drop any pending throttled refresh — it would re-snapshot
      // and possibly resurrect entries that were just cleared.
      _pendingRefresh?.cancel();
      _pendingRefresh = null;
      setState(() {
        _entries = LogBuffer.instance.snapshot();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollToBottom();
    });
  }

  @override
  void dispose() {
    _pendingRefresh?.cancel();
    _sub?.cancel();
    _clearSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Coalesce a flurry of incoming entries into a single setState,
  /// fired at most once per [_kLogTailThrottle]. The first entry
  /// schedules the timer; subsequent entries during the window are
  /// no-ops because the timer is already armed.
  void _scheduleRefresh() {
    if (!mounted) return;
    if (_pendingRefresh?.isActive ?? false) return;
    _pendingRefresh = Timer(_kLogTailThrottle, () {
      if (!mounted) return;
      setState(() {
        _entries = LogBuffer.instance.snapshot();
      });
      if (_autoScroll) {
        _scheduleScrollToBottom();
      }
    });
  }

  void _scheduleScrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  List<LogEntry> get _visible {
    if (_filterLevel == null) return _entries;
    return _entries.where((e) => e.level == _filterLevel).toList();
  }

  Future<void> _copyAll() async {
    final visible = _visible;
    final buf = StringBuffer();
    for (final entry in visible) {
      buf
        ..write('[${_formatTimestamp(entry.timestamp)}] ')
        ..write('${entry.level.name.toUpperCase()}: ')
        ..writeln(entry.message);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    // Route through NotificationService for consistent styling / the
    // global messenger key (plan F-29).
    NotificationService.showSuccess(
      'Copied ${visible.length} log lines.',
      context: context,
    );
  }

  void _clear() {
    // Relying on the `clears` stream subscription to re-snapshot and
    // setState — no need to duplicate the work here. See initState.
    LogBuffer.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all (visible)',
            onPressed: visible.isEmpty ? null : _copyAll,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Clear log buffer',
            onPressed: _entries.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _LogsToolbar(
            total: _entries.length,
            visibleCount: visible.length,
            autoScroll: _autoScroll,
            onAutoScrollChanged: (v) {
              setState(() => _autoScroll = v);
              if (v) _scheduleScrollToBottom();
            },
            filterLevel: _filterLevel,
            onFilterChanged: (level) {
              setState(() => _filterLevel = level);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      _entries.isEmpty
                          ? 'No logs yet. Interact with the app and they\'ll '
                              'appear here.'
                          : 'No logs match the current filter.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: visible.length,
                    itemBuilder: (context, i) =>
                        _LogRow(entry: visible[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogsToolbar extends StatelessWidget {
  final int total;
  final int visibleCount;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;
  final LogLevel? filterLevel;
  final ValueChanged<LogLevel?> onFilterChanged;

  const _LogsToolbar({
    required this.total,
    required this.visibleCount,
    required this.autoScroll,
    required this.onAutoScrollChanged,
    required this.filterLevel,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            visibleCount == total
                ? '$total entries'
                : '$visibleCount of $total entries',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 16),
          for (final level in LogLevel.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilterChip(
                label: Text(level.name),
                selected: filterLevel == level,
                onSelected: (selected) {
                  onFilterChanged(selected ? level : null);
                },
                visualDensity: VisualDensity.compact,
              ),
            ),
          const Spacer(),
          Row(
            children: [
              Switch(
                value: autoScroll,
                onChanged: onAutoScrollChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Text('Auto-scroll', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (entry.level) {
      LogLevel.info => theme.colorScheme.onSurface.withValues(alpha: 0.85),
      LogLevel.warn => const Color(0xFFFFB74D),
      LogLevel.error => theme.colorScheme.error,
    };
    final tag = switch (entry.level) {
      LogLevel.info => 'INFO ',
      LogLevel.warn => 'WARN ',
      LogLevel.error => 'ERROR',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerTheme.color?.withValues(alpha: 0.3) ??
                Colors.transparent,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: SelectableText(
              _formatTimestamp(entry.timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              tag,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.message,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}
