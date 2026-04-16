/// Subset of NVAPI status codes we explicitly react to in the UI. Full list
/// lives in the NVAPI SDK at `nvapi_lite_common.h`.
abstract final class NvapiStatus {
  /// `NVAPI_INVALID_USER_PRIVILEGE` — the call requires Administrator
  /// privileges. This is what NVIDIA returns when a non-elevated process
  /// tries to write certain DRS settings (including the undocumented
  /// capture-exclusion setting `0x809D5F60`).
  static const int invalidUserPrivilege = -137;

  static const int profileNotFound = -163;
  static const int executableNotFound = -166;
  static const int settingNotFound = -160;
}

/// Returns a human-friendly error message for the given NVAPI status code,
/// optionally prefixed with [fallback] for statuses we don't have a specific
/// explanation for.
String humanizeNvapiStatus(int? status, String fallback) {
  if (status == null) return fallback;
  switch (status) {
    case NvapiStatus.invalidUserPrivilege:
      return 'ShadowPlay Toggler needs to run as Administrator to modify '
          'NVIDIA driver settings. Please restart the app with '
          '"Run as administrator" and try again.';
    case NvapiStatus.profileNotFound:
      return 'NVIDIA profile not found.';
    case NvapiStatus.executableNotFound:
      return 'Executable is not attached to any NVIDIA profile.';
    case NvapiStatus.settingNotFound:
      return 'Setting is not configured on the selected profile.';
    default:
      return '$fallback (NVAPI code $status)';
  }
}
