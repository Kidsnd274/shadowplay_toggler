import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/backup_info.dart';
import 'nvapi_service.dart';

class BackupServiceException implements Exception {
  final String message;
  const BackupServiceException(this.message);

  @override
  String toString() => 'BackupServiceException: $message';
}

/// Thin orchestration over NVAPI save/load-from-file plus filesystem helpers
/// for managing the on-disk backup directory described in plan 24.
class BackupService {
  final NvapiService _nvapi;

  BackupService(this._nvapi);

  /// Creates a backup in the default backups directory (or at [customPath]
  /// if provided). Returns the absolute path of the written file.
  Future<String> createBackup({String? customPath}) async {
    final targetPath = customPath ?? await _nvapi.getDefaultBackupPath();
    if (targetPath.isEmpty) {
      throw const BackupServiceException(
        'Could not determine backup path (APPDATA not available).',
      );
    }

    // Ensure the parent directory exists. The default path is generated
    // inside `bridge_get_default_backup_path` which already creates the
    // directory, but a user-supplied path may point anywhere.
    final parent = Directory(p.dirname(targetPath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    try {
      await _nvapi.exportSettings(targetPath);
    } on NvapiBridgeException catch (e) {
      throw BackupServiceException('Failed to create backup: ${e.message}');
    }
    return targetPath;
  }

  /// Imports DRS settings from [filePath]. The caller is responsible for
  /// having created an auto-backup of the current state first (see
  /// `BackupService.createBackup` + the dialog flow).
  Future<void> restoreBackup(String filePath) async {
    if (!File(filePath).existsSync()) {
      throw BackupServiceException('Backup file not found: $filePath');
    }
    try {
      await _nvapi.importSettings(filePath);
    } on NvapiBridgeException catch (e) {
      throw BackupServiceException('Failed to restore backup: ${e.message}');
    }
  }

  /// Lists backups present in the default backup directory. Returns an
  /// empty list if the directory doesn't yet exist.
  Future<List<BackupInfo>> listBackups() async {
    final defaultPath = await _nvapi.getDefaultBackupPath();
    if (defaultPath.isEmpty) return [];

    final dir = Directory(p.dirname(defaultPath));
    if (!dir.existsSync()) return [];

    final out = <BackupInfo>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!(name.endsWith('.nvidiaprofile') ||
          name.endsWith('.nvidiaprofileinspector') ||
          name.endsWith('.nip'))) {
        continue;
      }
      final stat = entity.statSync();
      out.add(BackupInfo(
        filePath: entity.path,
        fileName: p.basename(entity.path),
        createdAt: stat.modified,
        fileSizeBytes: stat.size,
      ));
    }

    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Delete a backup file produced by [createBackup].
  ///
  /// Hard-requires the target to live inside [defaultBackupDirectory].
  /// A caller passing `C:\Windows\System32\kernel32.dll` by accident
  /// (or a bug that wires the wrong string into the button handler)
  /// should get an exception, not a deleted OS file. Plan F-13.
  Future<void> deleteBackup(String filePath) async {
    final dir = await defaultBackupDirectory();
    if (dir.isEmpty) {
      throw const BackupServiceException(
        'Backup directory could not be resolved — refusing to delete.',
      );
    }

    final canonicalFile = p.canonicalize(filePath);
    final canonicalDir = p.canonicalize(dir);
    if (!p.isWithin(canonicalDir, canonicalFile)) {
      throw BackupServiceException(
        'Refusing to delete "$filePath" — it is not inside the '
        'backup directory ($canonicalDir).',
      );
    }

    final file = File(canonicalFile);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  /// Returns the default backup directory. Useful for the "Open folder"
  /// action in the dialog.
  Future<String> defaultBackupDirectory() async {
    final fullPath = await _nvapi.getDefaultBackupPath();
    if (fullPath.isEmpty) return '';
    return p.dirname(fullPath);
  }
}
