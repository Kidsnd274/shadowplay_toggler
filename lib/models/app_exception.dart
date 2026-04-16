/// Base type for all exceptions thrown by ShadowPlay Toggler's own
/// service/infrastructure layers. UI layers can catch this and show a
/// user-friendly message via [NotificationService] while logging
/// [technicalDetails] for diagnostics.
class AppException implements Exception {
  /// Short, user-friendly message safe to show in a snackbar or dialog.
  final String message;

  /// Optional technical details (exception string, native error code,
  /// SQL error, etc.) — shown only in the expandable "Details" section of
  /// an error dialog or in logs.
  final String? technicalDetails;

  const AppException(this.message, {this.technicalDetails});

  @override
  String toString() => technicalDetails == null
      ? '$runtimeType: $message'
      : '$runtimeType: $message ($technicalDetails)';
}

/// Failures originating from the native NVAPI bridge.
class NvapiException extends AppException {
  /// Raw NVAPI status code, when available (see `NvapiStatus`).
  final int? statusCode;

  const NvapiException(
    super.message, {
    this.statusCode,
    super.technicalDetails,
  });
}

/// Failures originating from the local SQLite database.
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.technicalDetails});
}

/// Failures originating from the filesystem (picking files, backup paths,
/// etc.).
class FileException extends AppException {
  const FileException(super.message, {super.technicalDetails});
}
