import 'dart:io';

import 'database_service.dart';

class ResetDatabaseException implements Exception {
  final String message;
  const ResetDatabaseException(this.message);

  @override
  String toString() => 'ResetDatabaseException: $message';
}

/// Wipes the local SQLite database (managed_rules + app_state) and
/// re-initialises an empty one. Used by the "Reset Database" action in
/// Settings.
///
/// What this does NOT do:
///   * It never touches the NVIDIA driver. Existing exclusions on the
///     driver stay in place — the next scan will surface them in the
///     Detected tab as if they came from another tool.
///   * It does not delete backup files on disk.
///
/// The service tears the database down via [DatabaseService.close], then
/// deletes the file, then re-initialises so the app continues to work
/// without a restart.
class ResetDatabaseService {
  final DatabaseService _dbService;

  ResetDatabaseService(this._dbService);

  Future<void> reset() async {
    final dbPath = _dbService.path;
    if (dbPath == null) {
      throw const ResetDatabaseException(
        'Database has not been initialised yet — nothing to reset.',
      );
    }

    try {
      await _dbService.close();
    } catch (e) {
      throw ResetDatabaseException('Failed to close database: $e');
    }

    final file = File(dbPath);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (e) {
        // Re-open so the app stays functional even if the delete failed
        // (e.g. file lock from antivirus scanning the file).
        await _dbService.initialize();
        throw ResetDatabaseException('Failed to delete database file: $e');
      }
    }

    // sqflite/sqlite3 also keeps `-wal` / `-shm` sidecar files for the
    // write-ahead log. They normally self-clean when the DB is deleted
    // cleanly, but be defensive — a leftover WAL would resurrect rows.
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File(dbPath + suffix);
      if (sidecar.existsSync()) {
        try {
          sidecar.deleteSync();
        } catch (_) {
          // Best-effort; the next open() may overwrite or ignore them.
        }
      }
    }

    try {
      await _dbService.initialize();
    } catch (e) {
      throw ResetDatabaseException('Failed to re-open database: $e');
    }
  }
}
