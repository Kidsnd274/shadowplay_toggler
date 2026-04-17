/// Aggregate outcome of [BatchService.batchEnable] /
/// [BatchService.batchDisable]. Individual failures are surfaced via
/// [errors] so the UI can list them in a summary dialog, and via
/// [errorsByExePath] so callers can tell which specific rules to leave
/// unchanged (e.g. skip optimistic UI updates for failed rows — see
/// plan F-10).
class BatchResult {
  final int total;
  final int succeeded;
  final int failed;

  /// Human-readable `exeName: message` strings — suitable for dumping
  /// into a snackbar details blob or an error dialog.
  final List<String> errors;

  /// `exePath -> message` map — machine-friendly and intended for
  /// callers that need to correlate a failure back to the row it came
  /// from (e.g. *don't* flip that row's live-state on screen if the
  /// driver call actually failed). Keys are exePaths of rules that
  /// failed; successful rules do not appear here.
  final Map<String, String> errorsByExePath;

  const BatchResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    this.errors = const [],
    this.errorsByExePath = const {},
  });

  bool get hasFailures => failed > 0;

  bool didFailFor(String exePath) => errorsByExePath.containsKey(exePath);
}
