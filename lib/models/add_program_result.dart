/// Result of the "Add Program" orchestration in `AddProgramService`.
///
/// [needsUserConfirmation] is true for the intermediate state where we've
/// looked up the exe against the DRS database but haven't written anything
/// yet — the UI uses this to pop a "this exe already belongs to profile X,
/// apply exclusion to it?" style confirmation.
class AddProgramResult {
  final bool success;
  final String? errorMessage;
  final String exePath;
  final String exeName;
  final String profileName;
  final bool profileAlreadyExisted;
  final bool exclusionAlreadyApplied;
  final bool needsUserConfirmation;
  final String? confirmationMessage;

  const AddProgramResult({
    required this.success,
    required this.exePath,
    required this.exeName,
    required this.profileName,
    required this.profileAlreadyExisted,
    required this.exclusionAlreadyApplied,
    required this.needsUserConfirmation,
    this.errorMessage,
    this.confirmationMessage,
  });

  factory AddProgramResult.error({
    required String exePath,
    required String exeName,
    required String message,
  }) {
    return AddProgramResult(
      success: false,
      exePath: exePath,
      exeName: exeName,
      profileName: '',
      profileAlreadyExisted: false,
      exclusionAlreadyApplied: false,
      needsUserConfirmation: false,
      errorMessage: message,
    );
  }
}
