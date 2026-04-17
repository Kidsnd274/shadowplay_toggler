import '../constants/app_constants.dart';
import '../constants/nvapi_status.dart';
import '../models/managed_rule.dart';
import 'managed_rules_repository.dart';
import 'nvapi_service.dart';

/// Result of a single "apply the capture-exclusion to this exe and make
/// the local DB reflect that" round-trip.
///
/// Why this type exists: previously three services each rolled their
/// own shape of the same primitive (`AddProgramService.commit`,
/// `AdoptRuleService.adoptAndAddExclusion`, and
/// `ManagedRuleActionsService._enable`). They all called
/// [NvapiService.applyExclusion], unpacked the same JSON keys, and all
/// wrote back a `ManagedRule` row — with subtly different error
/// humanization, `profileName` fallback, and "already on the target
/// value" detection. Bugs migrated across them inconsistently
/// (e.g. the "use existing rule id" pattern). Centralising here means
/// there is exactly one correct implementation.
class ApplyExclusionOutcome {
  const ApplyExclusionOutcome._({
    required this.success,
    required this.exePath,
    this.errorMessage,
    this.updatedRule,
    this.profileName,
    this.profileWasPredefined = false,
    this.profileWasCreated = false,
    this.alreadyAttached = false,
    this.exclusionAlreadyApplied = false,
    this.previousValue,
  });

  /// `true` when the NVAPI call succeeded *and* the local row was
  /// written. A partial success (driver updated but DB write failed)
  /// surfaces as `success: false` with a populated [errorMessage] —
  /// the driver may already be holding the new value, but the rest of
  /// the app must not assume we "own" the row yet.
  final bool success;

  /// Normalised exe path the call operated on. Always set, even in
  /// the failure path, so the UI can echo it back to the user.
  final String exePath;

  /// Human-readable error when [success] is false. Already ran
  /// through [humanizeNvapiStatus] when the failure came from NVAPI.
  final String? errorMessage;

  /// The `ManagedRule` row after the write. `null` on failure. Code
  /// paths that want to show the updated detail pane should prefer
  /// this over re-querying the repo.
  final ManagedRule? updatedRule;

  /// The DRS profile the exe is now attached to. Taken from the live
  /// NVAPI response, falling back to the existing row / exe name when
  /// the bridge didn't echo it (shouldn't happen in practice).
  final String? profileName;

  /// True if the attached profile is an NVIDIA-predefined profile.
  /// Mirrors `profileWasPredefined` in the managed-rules DB row.
  final bool profileWasPredefined;

  /// True when NVAPI created a brand-new profile for this exe as
  /// part of applying the exclusion. Used by the Add-Program flow's
  /// post-commit messaging ("Added 'foo.exe' — new profile created").
  final bool profileWasCreated;

  /// True when the exe was already attached to some profile before
  /// this call. Together with [exclusionAlreadyApplied] it tells the
  /// caller whether anything actually changed on the driver side.
  final bool alreadyAttached;

  /// True when the driver was already at the target value. Implies
  /// the driver-side write was a no-op.
  final bool exclusionAlreadyApplied;

  /// Driver value *before* the call, in raw DWORD form. `null` if
  /// the exe had no attachment at all.
  final int? previousValue;
}

/// Single primitive for "apply the capture-exclusion on this exe's DRS
/// profile and keep `managed_rules` in sync".
///
/// Three call sites delegate here today:
///  * [AddProgramService.commit] — wraps this with the "is it
///    actually an .exe / does the file exist" gate.
///  * [AdoptRuleService.adoptAndAddExclusion] — calls adopt first,
///    then delegates.
///  * [ManagedRuleActionsService.setExclusionEnabled] (enable branch)
///    — delegates with the existing row in hand.
///
/// The service is deliberately small — a single public method — so
/// adding a fourth caller later doesn't regrow the duplication.
class ApplyExclusionService {
  ApplyExclusionService(this._nvapi, this._repo);

  final NvapiService _nvapi;
  final ManagedRulesRepository _repo;

  /// Apply the capture-disable setting to [exePath] and insert/update
  /// the corresponding `managed_rules` row.
  ///
  /// [preFetchedExisting] is an optimisation for callers that already
  /// have the row in hand (e.g. the managed detail pane). Pass it
  /// through so we don't re-query the DB for nothing. Callers without
  /// it can leave it null; we'll look it up ourselves.
  ///
  /// [operationLabel] is embedded into error messages ("Failed to
  /// $operationLabel: …") so the UI surface can stay specific to the
  /// user-facing flow (adopt vs add vs enable).
  Future<ApplyExclusionOutcome> apply(
    String exePath, {
    ManagedRule? preFetchedExisting,
    String operationLabel = 'apply exclusion',
  }) async {
    Map<String, dynamic>? response;
    try {
      response = await _nvapi.applyExclusion(exePath);
    } on NvapiBridgeException catch (e) {
      return ApplyExclusionOutcome._(
        success: false,
        exePath: exePath,
        errorMessage: 'NVAPI error: ${e.message}',
      );
    }

    if (response == null || (response['success'] as bool? ?? false) == false) {
      final raw = (response?['error'] as String?) ?? 'unknown NVAPI failure';
      final code = (response?['nvapiStatus'] as num?)?.toInt();
      return ApplyExclusionOutcome._(
        success: false,
        exePath: exePath,
        errorMessage:
            humanizeNvapiStatus(code, 'Failed to $operationLabel: $raw'),
      );
    }

    final profileName =
        (response['profileName'] as String?)?.trim().isNotEmpty == true
            ? response['profileName'] as String
            : (preFetchedExisting?.profileName ?? _fallbackProfileName(exePath));
    final profileWasCreated = (response['profileWasCreated'] as bool?) ?? false;
    final profileWasPredefined =
        (response['profileWasPredefined'] as bool?) ??
            (preFetchedExisting?.profileWasPredefined ?? false);
    final alreadyAttached = (response['alreadyAttached'] as bool?) ?? false;
    final previousValue = _parseHex(response['previousValue'] as String?);
    final exclusionAlreadyApplied = alreadyAttached &&
        previousValue == AppConstants.captureDisableValue;

    final now = DateTime.now();
    final existing =
        preFetchedExisting ?? await _repo.getRuleByExePath(exePath);

    final rule = ManagedRule(
      id: existing?.id,
      exePath: exePath,
      exeName:
          existing?.exeName ?? _fallbackExeName(exePath),
      profileName: profileName,
      profileWasPredefined: profileWasPredefined,
      profileWasCreated: profileWasCreated,
      intendedValue: AppConstants.captureDisableValue,
      previousValue: previousValue ?? existing?.previousValue,
      driverVersion: existing?.driverVersion,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await _repo.insertRule(rule);
    } catch (e) {
      // Driver is already holding the new value but we couldn't
      // persist the row — surface this honestly so the caller can
      // decide whether to retry or tell the user the UI will look
      // out of sync until the next scan.
      return ApplyExclusionOutcome._(
        success: false,
        exePath: exePath,
        errorMessage: 'Driver updated, but saving local row failed: $e',
        profileName: profileName,
        profileWasPredefined: profileWasPredefined,
        profileWasCreated: profileWasCreated,
        alreadyAttached: alreadyAttached,
        exclusionAlreadyApplied: exclusionAlreadyApplied,
        previousValue: previousValue,
      );
    }

    return ApplyExclusionOutcome._(
      success: true,
      exePath: exePath,
      updatedRule: rule,
      profileName: profileName,
      profileWasPredefined: profileWasPredefined,
      profileWasCreated: profileWasCreated,
      alreadyAttached: alreadyAttached,
      exclusionAlreadyApplied: exclusionAlreadyApplied,
      previousValue: previousValue,
    );
  }

  String _fallbackExeName(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  String _fallbackProfileName(String path) => _fallbackExeName(path);

  int? _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.startsWith('0x') || hex.startsWith('0X')
        ? hex.substring(2)
        : hex;
    return int.tryParse(cleaned, radix: 16);
  }
}
