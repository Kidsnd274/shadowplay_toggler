import 'dart:async';

/// Severity bucket for an entry in the in-process [LogBuffer].
enum LogLevel { info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}

/// Process-wide ring buffer of log lines surfaced from `print`,
/// `debugPrint`, framework errors and the native bridge (via stderr
/// in debug; via OutputDebugString in release).
///
/// The Logs screen subscribes to [stream] for live tailing and reads
/// [snapshot] for the initial paint. The buffer is bounded so a chatty
/// log day can't OOM the app.
class LogBuffer {
  static final LogBuffer instance = LogBuffer._();
  LogBuffer._();

  /// Hard cap on retained entries. Older lines are evicted FIFO.
  static const int maxEntries = 5000;

  final List<LogEntry> _entries = <LogEntry>[];
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  void add(LogLevel level, String message) {
    if (message.isEmpty) return;
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _controller.add(entry);
  }

  /// Convenience for callers that want to forward a multi-line block at
  /// a single severity (e.g. a stack trace). Each non-empty line is
  /// recorded as its own entry so the table view wraps cleanly.
  void addBlock(LogLevel level, String message) {
    for (final line in message.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      add(level, trimmed);
    }
  }

  /// Immutable copy of the current buffer in insertion order. Returns a
  /// new list each call so callers can safely iterate without worrying
  /// about concurrent mutation.
  List<LogEntry> snapshot() => List<LogEntry>.unmodifiable(_entries);

  Stream<LogEntry> get stream => _controller.stream;

  void clear() {
    _entries.clear();
  }
}
