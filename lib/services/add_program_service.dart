import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../constants/nvapi_status.dart';
import '../models/add_program_result.dart';
import '../models/managed_rule.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Lightweight preview returned by [AddProgramService.preview]. The preview
/// is the read-only half of the add flow — it never writes to the driver
/// database and is safe to call from UI-facing code to decide what
/// confirmation dialog to show.
class AddProgramPreview {
  final String exePath;
  final String exeName;

  /// If the exe already belongs to a DRS profile, the *real* name of that
  /// profile (which may differ from the exe filename — e.g. if NVIDIA ships
  /// "Foo Games" with `foo.exe` attached).
  final String? matchedProfileName;

  /// True when `NvAPI_DRS_FindApplicationByName` already returned a profile
  /// for this exe. Implies [matchedProfileName] is set.
  final bool profileAlreadyExisted;

  /// True when the matched profile is an NVIDIA-predefined profile.
  final bool profileIsPredefined;

  /// True when the exact same `exePath` is already recorded in the local
  /// managed-rules database. The UI should show an "already managed" hint
  /// instead of the usual confirmation dialog.
  final bool alreadyInLocalDb;

  /// Non-null if the preview lookup itself failed (e.g. NVAPI unavailable,
  /// file doesn't exist). The UI treats this as a fatal-for-this-attempt
  /// error and surfaces [errorMessage] directly.
  final String? errorMessage;

  const AddProgramPreview({
    required this.exePath,
    required this.exeName,
    required this.profileAlreadyExisted,
    required this.profileIsPredefined,
    required this.alreadyInLocalDb,
    this.matchedProfileName,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null;
}

/// Orchestrates the Add Program flow described in `plans/21-add-program-flow.md`.
///
/// The flow is split into two phases so the UI can show a confirmation
/// dialog between them:
///   1. [preview] — reads the live DRS database to classify the exe.
///   2. [commit]  — writes the exclusion and persists the managed rule.
class AddProgramService {
  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;

  AddProgramService(this._nvapi, this._repo);

  /// Classify an exe path against the live driver state without writing.
  Future<AddProgramPreview> preview(String exePath) async {
    final normalizedPath = p.normalize(exePath);
    final exeName = p.basename(normalizedPath);

    if (!_looksLikeExe(normalizedPath)) {
      return AddProgramPreview(
        exePath: normalizedPath,
        exeName: exeName,
        profileAlreadyExisted: false,
        profileIsPredefined: false,
        alreadyInLocalDb: false,
        errorMessage: 'Selected file is not an executable (.exe).',
      );
    }

    if (!File(normalizedPath).existsSync()) {
      return AddProgramPreview(
        exePath: normalizedPath,
        exeName: exeName,
        profileAlreadyExisted: false,
        profileIsPredefined: false,
        alreadyInLocalDb: false,
        errorMessage: 'File not found: $normalizedPath',
      );
    }

    // Already recorded in the local DB?
    final existing = await _repo.getRuleByExePath(normalizedPath);
    final alreadyInDb = existing != null;

    // Live driver lookup. findApplication returns {"found":false} on a miss,
    // which we translate into the "new profile will be created" branch.
    Map<String, dynamic>? findResult;
    try {
      findResult = _nvapi.findApplication(normalizedPath);
    } on NvapiBridgeException catch (e) {
      return AddProgramPreview(
        exePath: normalizedPath,
        exeName: exeName,
        profileAlreadyExisted: false,
        profileIsPredefined: false,
        alreadyInLocalDb: alreadyInDb,
        errorMessage: 'NVAPI error: ${e.message}',
      );
    }

    final found = (findResult?['found'] as bool?) ?? false;

    if (found) {
      return AddProgramPreview(
        exePath: normalizedPath,
        exeName: exeName,
        matchedProfileName: findResult?['profileName'] as String?,
        profileAlreadyExisted: true,
        profileIsPredefined:
            (findResult?['profileIsPredefined'] as bool?) ?? false,
        alreadyInLocalDb: alreadyInDb,
      );
    }

    return AddProgramPreview(
      exePath: normalizedPath,
      exeName: exeName,
      profileAlreadyExisted: false,
      profileIsPredefined: false,
      alreadyInLocalDb: alreadyInDb,
    );
  }

  /// Apply the exclusion and persist the managed rule. Safe to call even
  /// without a prior [preview]; the native layer handles create-or-reuse
  /// profile semantics atomically.
  Future<AddProgramResult> commit(String exePath) async {
    final normalizedPath = p.normalize(exePath);
    final exeName = p.basename(normalizedPath);

    if (!_looksLikeExe(normalizedPath)) {
      return AddProgramResult.error(
        exePath: normalizedPath,
        exeName: exeName,
        message: 'Selected file is not an executable (.exe).',
      );
    }
    if (!File(normalizedPath).existsSync()) {
      return AddProgramResult.error(
        exePath: normalizedPath,
        exeName: exeName,
        message: 'File not found: $normalizedPath',
      );
    }

    Map<String, dynamic>? response;
    try {
      response = _nvapi.applyExclusion(normalizedPath);
    } on NvapiBridgeException catch (e) {
      return AddProgramResult.error(
        exePath: normalizedPath,
        exeName: exeName,
        message: 'NVAPI error: ${e.message}',
      );
    }

    if (response == null || (response['success'] as bool? ?? false) == false) {
      final rawMsg = (response?['error'] as String?) ?? 'Unknown NVAPI failure';
      final nvapiStatus = (response?['nvapiStatus'] as num?)?.toInt();
      final message = humanizeNvapiStatus(
        nvapiStatus,
        'Failed to apply exclusion: $rawMsg',
      );
      return AddProgramResult.error(
        exePath: normalizedPath,
        exeName: exeName,
        message: message,
      );
    }

    final profileName =
        (response['profileName'] as String?)?.trim().isNotEmpty == true
            ? response['profileName'] as String
            : exeName;
    final profileWasCreated = (response['profileWasCreated'] as bool?) ?? false;
    final profileWasPredefined =
        (response['profileWasPredefined'] as bool?) ?? false;
    final alreadyAttached = (response['alreadyAttached'] as bool?) ?? false;
    final previousValueHex = response['previousValue'] as String?;
    final previousValue = _parseHexOrNull(previousValueHex);

    final now = DateTime.now();
    final existing = await _repo.getRuleByExePath(normalizedPath);

    final rule = ManagedRule(
      id: existing?.id,
      exePath: normalizedPath,
      exeName: exeName,
      profileName: profileName,
      profileWasPredefined: profileWasPredefined,
      profileWasCreated: profileWasCreated,
      intendedValue: AppConstants.captureDisableValue,
      previousValue: previousValue ?? existing?.previousValue,
      driverVersion: existing?.driverVersion,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await _repo.insertRule(rule);

    // If the exe was already attached to a profile and the previous value
    // matches our target, report "exclusion already applied" — the call was
    // a no-op on the driver side.
    final exclusionAlreadyApplied = alreadyAttached &&
        previousValue == AppConstants.captureDisableValue;

    return AddProgramResult(
      success: true,
      exePath: normalizedPath,
      exeName: exeName,
      profileName: profileName,
      profileAlreadyExisted: alreadyAttached,
      exclusionAlreadyApplied: exclusionAlreadyApplied,
      needsUserConfirmation: false,
    );
  }

  bool _looksLikeExe(String path) =>
      p.extension(path).toLowerCase() == '.exe';

  int? _parseHexOrNull(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.startsWith('0x') || hex.startsWith('0X')
        ? hex.substring(2)
        : hex;
    return int.tryParse(cleaned, radix: 16);
  }
}
