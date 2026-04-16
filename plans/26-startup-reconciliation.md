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

## Tasks

1. **Create `lib/services/reconciliation_service.dart`**
   - Method:
     ```dart
     Future<ReconciliationResult> reconcile();
     ```
   - Logic:
     1. Load all managed rules from the local database.
     2. Open NVAPI session and load settings.
     3. For each managed rule in the local DB:
        a. Check if the profile still exists in the driver.
        b. Check if the setting still has the expected value.
        c. Classify:
           - **In sync**: profile exists, setting matches intended value. No action.
           - **Drifted**: profile exists, but setting value changed. Mark as warning.
           - **Missing**: profile does not exist or app is not attached. Mark as orphaned.
     4. Scan for orphaned app-created profiles (prefix match but not in DB):
        - Auto-recover into the managed rules database.
     5. Return results.

2. **Create `lib/models/reconciliation_result.dart`**
   ```dart
   class ReconciliationResult {
     final int rulesInSync;
     final int rulesDrifted;
     final int rulesOrphaned;
     final int rulesRecovered;
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
- In-sync rules show green status.
- Drifted rules are detected and flagged with amber status.
- Orphaned rules are detected and flagged with red status.
- Auto-recovery of prefixed profiles works.
- NVAPI failure is handled gracefully with a clear error message.
- `flutter analyze` reports no errors.
