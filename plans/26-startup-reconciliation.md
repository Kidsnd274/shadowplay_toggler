# 26 - Startup Reconciliation

## Goal

Implement the reconciliation scan that runs on app startup to synchronize the local managed rules database with the actual NVIDIA driver state.

## Prerequisites

- Plan 13 (Local Database) completed.
- Plan 12 (Dart FFI Bindings) completed.
- Plan 23 (Scan Profiles) completed.

## Background

From `design.md`, on launch the app should:
- Scan the driver DB.
- Rebuild a detected-state snapshot.
- Auto-recover prefixed profiles into Managed.
- Place everything else into Detected Existing Rules.

This handles the case where the local DB is lost (app reinstall, data reset) or where driver changes were made outside the app (driver update, manual editing, NPI).

> **Driver-install resilience (important):** The local SQLite database survives driver
> reinstalls, but the NVIDIA DRS database resets to factory defaults on every driver
> install (even same-version repair installs). When this happens, *all* custom profiles
> and settings are wiped. The reconciliation must detect this and offer a bulk re-apply
> instead of treating each rule as individually orphaned. Detection signals:
> 1. `last_driver_version` in app_state differs from the current driver version.
> 2. `drs_profile_hash` in app_state differs from a freshly-computed hash, even when
>    the version string hasn't changed.

## Tasks

0. **Detect driver reinstall / DRS reset**
   - Before per-rule reconciliation, compare the stored `last_driver_version` and
     `drs_profile_hash` (from plan 13's `app_state` table) against the live driver.
   - If either has changed:
     1. Flag the reconciliation as a **DRS reset event**.
     2. Skip normal per-rule orphan detection; instead mark all managed rules as
        `needsReapply`.
     3. After reconciliation, present the user with a single prompt:
        "Driver change detected — X managed rules need to be re-applied. [Re-apply All] [Review]"
     4. On "Re-apply All": iterate all managed rules and call the bridge to recreate
        profiles / settings. Update `last_driver_version` and `drs_profile_hash`.
     5. On "Review": open the Managed tab with amber status on every rule so the user
        can selectively re-apply.
   - If both match, proceed with normal per-rule reconciliation below.

1. **Create `lib/services/reconciliation_service.dart`**
   - Method:
     ```dart
     Future<ReconciliationResult> reconcile();
     ```
   - Logic:
     1. Load all managed rules from the local database.
     2. Open NVAPI session and load settings.
     3. Check for DRS reset (task 0 above). If detected, return early with
        `drsResetDetected: true` and the list of rules needing re-apply.
     4. For each managed rule in the local DB:
        a. Check if the profile still exists in the driver.
        b. Check if the setting still has the expected value.
        c. Classify:
           - **In sync**: profile exists, setting matches intended value. No action.
           - **Drifted**: profile exists, but setting value changed. Mark as warning.
           - **Missing**: profile does not exist or app is not attached. Mark as orphaned.
     5. Scan for orphaned app-created profiles (prefix match but not in DB):
        - Auto-recover into the managed rules database.
     6. Update `last_driver_version` and `drs_profile_hash` in app_state.
     7. Return results.

2. **Create `lib/models/reconciliation_result.dart`**
   ```dart
   class ReconciliationResult {
     final bool drsResetDetected;
     final String? previousDriverVersion;
     final String? currentDriverVersion;
     final int rulesInSync;
     final int rulesDrifted;
     final int rulesOrphaned;
     final int rulesRecovered;
     final int rulesNeedingReapply;
     final List<String> warnings;
     final Duration duration;
   }
   ```

3. **Run reconciliation on app startup**
   - In the app initialization flow (e.g., in a startup provider or `initState` of the root widget):
     1. Initialize NVAPI.
     2. Run reconciliation.
     3. If any issues found, store results for display.

4. **Show reconciliation results**
   - If everything is in sync: no notification needed.
   - If rules drifted: show a notification banner at the top of the home screen:
     "X managed rules have changed in the driver since last session."
     [Review] [Dismiss]
   - If rules were recovered: show a snackbar:
     "Recovered X previously managed rules."
   - If rules are orphaned: show a warning:
     "X managed rules could not be found in the driver."
     [Remove from list] [Keep]

5. **Update rule status in the managed list**
   - After reconciliation, each managed rule should have a `syncStatus` field:
     - `inSync` = green indicator
     - `drifted` = amber indicator
     - `orphaned` = red indicator
   - This status is shown in the `RuleListTile` (plan 16).

6. **Handle NVAPI initialization failure on startup**
   - If NVAPI cannot initialize (no NVIDIA GPU, driver not installed):
     - Show a prominent error banner.
     - Disable all driver-related features.
     - Still allow viewing the local managed rules database (read-only mode).

## Acceptance Criteria

- Reconciliation runs automatically on app startup.
- **Driver reinstall / DRS reset is detected** via version and hash comparison.
- When a DRS reset is detected, the user is prompted to re-apply all managed rules in bulk.
- In-sync rules show green status.
- Drifted rules are detected and flagged with amber status.
- Orphaned rules are detected and flagged with red status.
- Auto-recovery of prefixed profiles works.
- `last_driver_version` and `drs_profile_hash` are updated after every successful reconciliation.
- NVAPI failure is handled gracefully with a clear error message.
- `flutter analyze` reports no errors.
