abstract final class AppConstants {
  static const String appTitle = 'ShadowPlay Toggler';

  /// DRS setting ID for the capture-exclusion flag. Community-identified,
  /// not officially documented by NVIDIA.
  static const int captureSettingId = 0x809D5F60;
  static const int captureEnableValue = 0x00000000;
  static const int captureDisableValue = 0x10000000;
}
