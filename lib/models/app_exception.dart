/// Base type for all exceptions thrown by ShadowPlay Toggler's own
/// service/infrastructure layers. UI layers can catch this and show a
/// user-friendly message via [NotificationService] while logging
/// [technicalDetails] for diagnostics.
///
/// Plan F-38: [cause] and [stackTrace] are optional carriers for the
/// original exception that triggered this one. Historically the
/// codebase would `catch (e) { throw AppException('foo'); }` and drop
/// the root cause on the floor, which made production triage painful.
/// Callers can now pass the original object + stack through so logs
/// can print the full chain (they're also shown in `toString()` when
/// present, gated behind a `showCause` flag to keep snackbar output
/// terse).
class AppException implements Exception {
  /// Short, user-friendly message safe to show in a snackbar or dialog.
  final String message;

  /// Optional technical details (exception string, native error code,
  /// SQL error, etc.) — shown only in the expandable "Details" section of
  /// an error dialog or in logs.
  final String? technicalDetails;

  /// Underlying error object that triggered this exception, if any.
  /// Typically a platform exception, FFI failure, or parsing error.
  /// Never shown to end users; logged for diagnostics.
  final Object? cause;

  /// Stack trace captured at the [cause]'s throw site, not this
  /// object's construction. Pass through from the `catch` clause:
  /// `} catch (e, st) { throw AppException('…', cause: e, stackTrace: st); }`.
  final StackTrace? stackTrace;

  const AppException(
    this.message, {
    this.technicalDetails,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    final buf = StringBuffer('$runtimeType: $message');
    if (technicalDetails != null) {
      buf.write(' ($technicalDetails)');
    }
    if (cause != null) {
      buf.write('\n  caused by: $cause');
    }
    return buf.toString();
  }
}

/// Failures originating from the native NVAPI bridge.
class NvapiException extends AppException {
  /// Raw NVAPI status code, when available (see `NvapiStatus`).
  final int? statusCode;

  const NvapiException(
    super.message, {
    this.statusCode,
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });
}

/// Failures originating from the local SQLite database.
class DatabaseException extends AppException {
  const DatabaseException(
    super.message, {
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });
}

/// Failures originating from the filesystem (picking files, backup paths,
/// etc.).
class FileException extends AppException {
  const FileException(
    super.message, {
    super.technicalDetails,
    super.cause,
    super.stackTrace,
  });
}
