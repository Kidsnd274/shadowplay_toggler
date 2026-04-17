/// Aggregate outcome of [BatchService.batchEnable] /
/// [BatchService.batchDisable]. Individual failures are surfaced via
/// [errors] so the UI can list them in a summary dialog.
class BatchResult {
  final int total;
  final int succeeded;
  final int failed;
  final List<String> errors;

  const BatchResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    this.errors = const [],
  });

  bool get hasFailures => failed > 0;
}
