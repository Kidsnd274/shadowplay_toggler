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
     3. Get all profiles via `nvapiService.getAllProfiles()`.
     4. For each profile:
        a. Query setting `0x809D5F60`.
        b. If the setting has a value (found = true):
           - Get the profile's applications.
           - Classify the rule:
             - If profile name starts with the managed prefix AND is in local DB: skip (already managed).
             - If profile name starts with the managed prefix but NOT in local DB: mark for auto-recovery.
             - If isPredefined and isCurrentPredefined: add to NVIDIA Defaults.
             - Otherwise: add to Detected Existing Rules.
     5. Check the Base Profile for the setting.
     6. Return categorized results.

2. **Create `lib/models/scan_result.dart`**
   ```dart
   class ScanResult {
     final List<ExclusionRule> detectedRules;
     final List<ExclusionRule> nvidiaDefaults;
     final List<ExclusionRule> recoveredManagedRules;
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

6. **Handle auto-recovery of orphaned managed rules**
   - If the scan finds profiles with the managed prefix that are not in the local DB:
     - Auto-add them to the managed rules database.
     - Show a notification: "Recovered X previously managed rules."

7. **Store scan timestamp**
   - Save the last scan time in the app state database.
   - Show "Last scanned: {timestamp}" somewhere in the UI.

## Acceptance Criteria

- Clicking "Scan NVIDIA Profiles" scans all DRS profiles.
- Progress is shown during the scan.
- Detected external rules appear in the Detected tab.
- NVIDIA defaults appear in the Defaults tab.
- Orphaned managed rules are auto-recovered.
- Scan duration and stats are reported.
- `flutter analyze` reports no errors.
