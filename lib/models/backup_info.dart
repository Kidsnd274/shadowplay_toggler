/// Metadata about a previously-created DRS backup on disk.
///
/// We do not embed any info from inside the `.nvidiaProfileInspector` file
/// itself — these files are binary NVAPI output and we never parse them
/// in-app. The fields here come straight from the filesystem.
class BackupInfo {
  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final int fileSizeBytes;

  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.fileSizeBytes,
  });

  String get humanSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
