import 'dart:convert';

import '../models/profile_info.dart';
import '../native/bridge_ffi.dart';

class NvapiBridgeException implements Exception {
  final String message;
  final int? statusCode;

  const NvapiBridgeException(this.message, {this.statusCode});

  @override
  String toString() => 'NvapiBridgeException: $message'
      '${statusCode != null ? ' (code $statusCode)' : ''}';
}

class NvapiService {
  final BridgeFfi _bridge;

  NvapiService(this._bridge);

  void _checkStatus(int result, String operation) {
    if (result != 0) {
      final msg = _bridge.getErrorMessage(result);
      throw NvapiBridgeException(
        '$operation failed: $msg',
        statusCode: result,
      );
    }
  }

  T? _parseJson<T>(String? json, T Function(dynamic) parser) {
    if (json == null) return null;
    final decoded = jsonDecode(json);
    return parser(decoded);
  }

  // ── Session helpers ─────────────────────────────────────────────

  void openSession() {
    _checkStatus(_bridge.openSession(), 'Open session');
  }

  void createSession() {
    _checkStatus(_bridge.createSession(), 'Create session');
  }

  void loadSettings() {
    _checkStatus(_bridge.loadSettings(), 'Load settings');
  }

  void saveSettings() {
    _checkStatus(_bridge.saveSettings(), 'Save settings');
  }

  void destroySession() {
    _checkStatus(_bridge.destroySession(), 'Destroy session');
  }

  // ── Profiles ────────────────────────────────────────────────────

  int getProfileCount() {
    final count = _bridge.getProfileCount();
    if (count < 0) {
      throw const NvapiBridgeException('Failed to get profile count');
    }
    return count;
  }

  List<ProfileInfo> getAllProfiles() {
    final json = _bridge.getAllProfilesJson();
    if (json == null) {
      throw const NvapiBridgeException('Failed to get profiles JSON');
    }
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Applications ────────────────────────────────────────────────

  List<Map<String, dynamic>> getProfileApps(int profileIndex) {
    final json = _bridge.getProfileAppsJson(profileIndex);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Map<String, dynamic>? findApplication(String exePath) {
    return _parseJson(
      _bridge.findApplication(exePath),
      (d) => d as Map<String, dynamic>,
    );
  }

  List<Map<String, dynamic>> getBaseProfileApps() {
    final json = _bridge.getBaseProfileAppsJson();
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  // ── Settings ────────────────────────────────────────────────────

  Map<String, dynamic>? getSetting(int profileIndex, int settingId) {
    return _parseJson(
      _bridge.getSetting(profileIndex, settingId),
      (d) => d as Map<String, dynamic>,
    );
  }

  void setDwordSetting(int profileIndex, int settingId, int value) {
    _checkStatus(
      _bridge.setDwordSetting(profileIndex, settingId, value),
      'Set DWORD setting',
    );
  }

  void deleteSetting(int profileIndex, int settingId) {
    _checkStatus(
      _bridge.deleteSetting(profileIndex, settingId),
      'Delete setting',
    );
  }

  void restoreSettingDefault(int profileIndex, int settingId) {
    _checkStatus(
      _bridge.restoreSettingDefault(profileIndex, settingId),
      'Restore setting default',
    );
  }

  void createProfile(String name) {
    _checkStatus(_bridge.createProfile(name), 'Create profile "$name"');
  }

  void addApplication(int profileIndex, String exePath) {
    _checkStatus(
      _bridge.addApplication(profileIndex, exePath),
      'Add application',
    );
  }

  Map<String, dynamic>? applyExclusion(String exePath) {
    return _parseJson(
      _bridge.applyExclusion(exePath),
      (d) => d as Map<String, dynamic>,
    );
  }

  // ── Backup / Restore ───────────────────────────────────────────

  void exportSettings(String filePath) {
    _checkStatus(_bridge.exportSettings(filePath), 'Export settings');
  }

  void importSettings(String filePath) {
    _checkStatus(_bridge.importSettings(filePath), 'Import settings');
  }

  String getDefaultBackupPath() => _bridge.getDefaultBackupPath();
}
