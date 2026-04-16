# 23 - Scan Profiles Feature

## Goal

Implement the full DRS profile scan that discovers all existing exclusion rules and populates the Detected and Defaults tabs.

## Prerequisites

- Plan 12 (Dart FFI Bindings) completed.
- Plan 17 (Detected Rules List) completed.
- Plan 18 (NVIDIA Defaults List) completed.

## Background

From `design.md`, the scan logic is:

1. Create DRS session and load settings.
2. Enumerate all profiles.
3. For each profile, get profile info.
4. Enumerate all associated applications.
5. Query setting `0x809D5F60`.
6. Record: profile name, app name, value, isPredefined, isCurrentPredefined, settingLocation.
7. Separately inspect Base Profile / Global Profile for inherited behavior.

## Tasks

1. **Create `lib/services/scan_service.dart`**
  - Orchestrates the full scan.
  - Method:
    ```dart
    Future<ScanResult> scanProfiles();
    ```
  - Logic:
  1. Ensure NVAPI is initialized (or initialize it).
  2. Open a DRS session.
  3. Load all rows from the local managed-rules DB into a lookup keyed by `(exePath, profileName)` (and also `profileName` alone for cross-reference).
  4. Get all profiles via `nvapiService.getAllProfiles()`.
  5. For each profile:
    a. Query setting `0x809D5F60`.
     b. If the setting has a value (found = true):
        - Get the profile's applications.
        - For each `(profile, app)` pair, classify the rule using **both** the live driver metadata and the local DB as the source of truth for "is this managed":
          - If the pair matches a row in the managed-rules DB: it is a managed rule. If values match, it's in-sync; otherwise it's drifted. (Either way, it does not go into Detected.)
          - Else if the setting is predefined for this profile (`isPredefined && isCurrentPredefined`): add to NVIDIA Defaults.
          - Else: add to Detected Existing Rules.
  6. Check the Base Profile for the setting (separately surfaced as inherited behavior).
  7. Also surface orphans: managed-DB rows whose profile or application attachment was not found during the scan. Report these as drift so the UI can offer reconciliation.
  8. Return categorized results.
2. **Create `lib/models/scan_result.dart`**
  ```dart
   class ScanResult {
     final List<ExclusionRule> detectedRules;      // external, not in local DB
     final List<ExclusionRule> nvidiaDefaults;     // predefined by NVIDIA
     final List<ExclusionRule> driftedManagedRules; // in local DB but live value differs
     final List<ExclusionRule> orphanedManagedRules; // in local DB but not found live
     final int totalProfilesScanned;
     final int totalSettingsFound;
     final Duration scanDuration;
     final String? error;
   }
  ```
3. **Add scan progress tracking**
  - Create a `scanProgressProvider` that tracks:
    - `isScanning: bool`
    - `currentProfile: String` (name of profile being scanned)
    - `progress: double` (0.0 to 1.0)
    - `profilesScanned: int`
    - `totalProfiles: int`
4. **Build scan progress UI**
  - While scanning, show a progress indicator in the toolbar or as an overlay.
  - Show current profile name being scanned.
  - Show progress bar or percentage.
  - Allow cancellation (nice-to-have).
5. **Wire up the toolbar button**
  - Connect "Scan NVIDIA Profiles" button to trigger the scan.
  - Disable the button while a scan is in progress.
  - After scan completes:
    - Update `detectedRulesProvider` with discovered external rules.
    - Update `nvidiaDefaultsProvider` with discovered defaults.
    - Show a summary snackbar: "Scan complete: found X external rules, Y NVIDIA defaults."
6. **Surface drift and orphans (no auto-recovery)**
  - The app does not auto-recover rules. Any detected external `0x809D5F60` override appears in the Detected tab where the user can adopt it (see plan 27).
  - Drifted managed rules (local DB says X, driver says Y) are shown with a visible status indicator in the Managed tab; the detail view exposes "Reapply" (push DB value back to driver) and "Accept current" (update DB from driver).
  - Orphaned managed rules (local DB row with no matching live profile/app) are shown with a warning; the detail view exposes "Remove from managed list" and, if the user chooses, "Re-create on driver".
7. **Store scan timestamp**
  - Save the last scan time in the app state database.
  - Show "Last scanned: {timestamp}" somewhere in the UI.

## Acceptance Criteria

- Clicking "Scan NVIDIA Profiles" scans all DRS profiles.
- Progress is shown during the scan.
- Detected external rules appear in the Detected tab.
- NVIDIA defaults appear in the Defaults tab.
- Drifted and orphaned managed rules are surfaced with clear status; no auto-recovery is performed.
- Scan duration and stats are reported.
- `flutter analyze` reports no errors.

