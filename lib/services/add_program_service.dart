import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/add_program_result.dart';
import 'apply_exclusion_service.dart';
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
  final ApplyExclusionService _apply;

  AddProgramService(this._nvapi, this._repo, this._apply);

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
      findResult = await _nvapi.findApplication(normalizedPath);
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
  ///
  /// Gates on the .exe / file-exists preconditions locally, then
  /// delegates the shared "apply + persist" primitive to
  /// [ApplyExclusionService] so this service, the Adopt flow, and the
  /// managed-rule Enable action all share the same logic path.
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

    final outcome = await _apply.apply(
      normalizedPath,
      operationLabel: 'apply exclusion',
    );

    if (!outcome.success) {
      return AddProgramResult.error(
        exePath: normalizedPath,
        exeName: exeName,
        message: outcome.errorMessage ?? 'Failed to apply exclusion.',
      );
    }

    return AddProgramResult(
      success: true,
      exePath: normalizedPath,
      exeName: exeName,
      profileName: outcome.profileName ?? exeName,
      profileAlreadyExisted: outcome.alreadyAttached,
      exclusionAlreadyApplied: outcome.exclusionAlreadyApplied,
      needsUserConfirmation: false,
    );
  }

  bool _looksLikeExe(String path) =>
      p.extension(path).toLowerCase() == '.exe';
}
