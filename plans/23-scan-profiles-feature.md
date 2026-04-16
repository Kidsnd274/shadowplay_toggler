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

> **Performance note.** All DRS operations run against an in-process cached copy
> of the DRS database (loaded once by `NvAPI_DRS_LoadSettings`). They touch
> neither the kernel driver nor the GPU. A full scan over ~500–2000 profiles is
> expected to take roughly 50–500 ms depending on cache warmth. See the
> "Performance Considerations" section below for the concrete choices that flow
> from this.

## Tasks

1. **Add a native `bridge_scan_exclusion_rules` entry point**
   Rather than crossing FFI once per profile (~2000 crossings for a full scan),
   add a single C++ function that walks the entire DRS database in one call
   and returns the result as a single JSON blob. Each crossing has a fixed
   overhead (~5 μs) that dominates the cost of the actual NVAPI calls on small
   per-profile work.
   - Signature:
     ```cpp
     BRIDGE_API const char* bridge_scan_exclusion_rules(unsigned int settingId);
     ```
   - Behavior:
     1. Iterate every profile via `NvAPI_DRS_EnumProfiles`.
     2. For each profile: `GetProfileInfo`, `GetSetting(settingId)`.
     3. If the setting is present, `EnumApplications` on that profile.
     4. Collect `(profileName, profileIsPredefined, appExePath, appIsPredefined,
        currentValue, predefinedValue, isCurrentPredefined, settingLocation)`
        tuples.
     5. Also inspect the Base Profile separately so inherited behavior can be
        surfaced by the caller.
     6. Return a single JSON document shaped like:
        ```json
        {
          "durationMs": 142,
          "profilesScanned": 1780,
          "rules": [
            {"profileName": "obs64.exe", "profileIsPredefined": false,
             "appExePath": "C:/Program Files/obs-studio/bin/64bit/obs64.exe",
             "appIsPredefined": false, "currentValue": "0x10000000",
             "predefinedValue": "0x00000000", "isCurrentPredefined": false,
             "settingLocation": "current_profile"},
            ...
          ],
          "baseProfile": { ... same shape, optional ... }
        }
        ```
   - Must use `alloc_json` / `bridge_free_json` so the existing Dart ownership
     rules apply.

2. **Add a matching Dart wrapper**
   - In `lib/native/bridge_ffi.dart` add `scanExclusionRules(int settingId)`
     that calls the native function and returns the raw JSON string.
   - In `lib/services/nvapi_service.dart` add a typed wrapper that parses the
     JSON into a list of `ScannedRule` records.

3. **Create `lib/services/scan_service.dart`**
   - Orchestrates the full scan.
   - Method:
     ```dart
     Future<ScanResult> scanProfiles();
     ```
   - Logic:
     1. Ensure NVAPI is initialized (or initialize it).
     2. Open a DRS session.
     3. Load all rows from the local managed-rules DB into a lookup keyed by
        `(exePath, profileName)` (and also `profileName` alone for
        cross-reference).
     4. Call `bridge_scan_exclusion_rules(0x809D5F60)` via the FFI wrapper.
        The native call does the whole enumeration in one shot.
     5. For each tuple returned, classify using **both** the live driver
        metadata and the local DB as the source of truth for "is this
        managed":
        - If the pair matches a row in the managed-rules DB: it is a managed
          rule. If values match, it's in-sync; otherwise it's drifted.
          (Either way, it does not go into Detected.)
        - Else if the setting is predefined for this profile (`isPredefined
          && isCurrentPredefined`): add to NVIDIA Defaults.
        - Else: add to Detected Existing Rules.
     6. Base-profile info from the JSON is surfaced separately as inherited
        behavior.
     7. Also surface orphans: managed-DB rows whose profile or application
        attachment was not found during the scan. Report these as drift so
        the UI can offer reconciliation.
     8. Return categorized results.
   - **Run the FFI call off the UI isolate.** Wrap the `bridge_scan_*` call
     (plus JSON parsing, which is itself a few ms for a big DB) in
     `Isolate.run(() => ...)` / `compute(...)` so the frame loop is never
     blocked. The native side is thread-safe for reads against a single
     already-loaded session, but keep all scan calls serialized through
     `scan_service.dart` to avoid two concurrent scans sharing the global
     `g_session`.

4. **Create `lib/models/scan_result.dart`**
   ```dart
   class ScanResult {
     final List<ExclusionRule> detectedRules;      // external, not in local DB
     final List<ExclusionRule> nvidiaDefaults;     // predefined by NVIDIA
     final List<ExclusionRule> driftedManagedRules; // in local DB but live value differs
     final List<ExclusionRule> orphanedManagedRules; // in local DB but not found live
     final ExclusionRule? baseProfileRule;          // inherited default, if any
     final int totalProfilesScanned;
     final int totalSettingsFound;
     final Duration scanDuration;
     final String? error;
   }
   ```

5. **Add scan progress tracking**
   - Create a `scanProgressProvider` that tracks:
     - `isScanning: bool`
     - `progress: double` (0.0 to 1.0, approximate since the native call is
       atomic from Dart's perspective — report a coarse 0 → 1 rather than a
       per-profile number).
   - Because the native call returns in one shot, per-profile progress isn't
     available without either streaming callbacks back into Dart (hard with
     FFI) or breaking up the scan (defeats the purpose of batching). The
     expected scan time is short enough (~200 ms median) that a determinate
     progress bar isn't needed.

6. **Build scan progress UI**
   - While scanning, show an indeterminate progress indicator (spinner or
     linear bar) in the toolbar.
   - **Debounce the spinner by 150 ms** — if the scan completes in under
     that, don't show a spinner at all. This avoids UI flicker for the common
     fast-path case on warm caches.
   - If the scan runs longer than ~2 seconds, show a secondary message such
     as "Scanning NVIDIA profiles — this is taking a while" so the user
     knows the app isn't frozen.
   - Cancellation is not supported in the v1 implementation because the
     native call is a single blocking unit; if scans ever regress past a
     second or two in the field, revisit by splitting the native function
     into a resumable iterator.

7. **Wire up the toolbar button**
   - Connect "Scan NVIDIA Profiles" button to trigger the scan.
   - Disable the button while a scan is in progress.
   - After scan completes:
     - Update `detectedRulesProvider` with discovered external rules.
     - Update `nvidiaDefaultsProvider` with discovered defaults.
     - Show a summary snackbar: "Scan complete: found X external rules, Y NVIDIA defaults."

8. **Surface drift and orphans (no auto-recovery)**
   - The app does not auto-recover rules. Any detected external `0x809D5F60`
     override appears in the Detected tab where the user can adopt it (see
     plan 27).
   - Drifted managed rules (local DB says X, driver says Y) are shown with a
     visible status indicator in the Managed tab; the detail view exposes
     "Reapply" (push DB value back to driver) and "Accept current" (update
     DB from driver).
   - Orphaned managed rules (local DB row with no matching live profile/app)
     are shown with a warning; the detail view exposes "Remove from managed
     list" and, if the user chooses, "Re-create on driver".

9. **Store scan timestamp**
   - Save the last scan time in the app state database.
   - Show "Last scanned: {timestamp}" somewhere in the UI.

## Performance Considerations

All DRS operations are user-mode calls against an in-memory cache that
`NvAPI_DRS_LoadSettings` populates once per session; they never touch the
kernel driver or the GPU, and they never hit disk. This drives the following
concrete design choices, already reflected in the tasks above:

1. **One native call, not N FFI crossings.** With ~2000 profiles each requiring
   2–3 NVAPI calls, a Dart-driven loop would perform ~4000–6000 FFI
   round-trips. FFI overhead (~5 μs per crossing) would dominate the actual
   NVAPI work. A single `bridge_scan_exclusion_rules` function collapses this
   to one crossing plus one JSON parse.

2. **Run the scan on a Dart isolate.** Even a 200 ms native call on the root
   isolate blocks ~12 frames and causes visible jank. `compute(...)` / 
   `Isolate.run(...)` moves both the FFI call and the JSON decode off the UI
   thread. (The spawned isolate must be able to open its own `DynamicLibrary`;
   passing function pointers across isolates isn't portable. The simplest
   pattern is to have the isolate's entry point construct its own
   `BridgeFfi` against the same DLL path.)

3. **No per-profile progress callbacks.** Implementing streaming progress
   would require either (a) an FFI callback mechanism (complex, costs a
   crossing per profile and defeats the batching win) or (b) breaking the
   scan into page-sized chunks (possible but premature). Since the whole
   scan is typically ≤ 500 ms, an indeterminate spinner debounced by 150 ms
   is sufficient UX.

4. **Serialize scans.** The bridge's `g_session` is a single global, so two
   concurrent scans would race. `scan_service.dart` should guard with a
   simple "is a scan already running?" flag and either queue or drop the
   second request.

5. **Budget and telemetry.** Log the scan duration via `bridge_log` on the
   native side and include `scanDuration` in `ScanResult`. Flag any scan
   that exceeds 2 seconds as a warning in the log — that would indicate
   NVAPI cache invalidation (e.g. a driver install happened mid-scan) and
   would be worth investigating.

6. **UI-side rendering cost.** The Detected and Defaults lists use
   `ListView.builder`, so only visible rows are built. 2000+ tiles in a
   tab is fine as long as we never materialize them all at once (we don't).

## Acceptance Criteria

- Clicking "Scan NVIDIA Profiles" scans all DRS profiles via a single native
  call executed on a Dart isolate; the UI thread is never blocked for longer
  than one frame.
- A median scan on a typical system (≤ 2000 profiles) completes in under
  500 ms; a 150 ms debounce ensures no spinner flicker on fast-path scans.
- Detected external rules appear in the Detected tab.
- NVIDIA defaults appear in the Defaults tab.
- Drifted and orphaned managed rules are surfaced with clear status; no
  auto-recovery is performed.
- Concurrent scan requests are serialized, not raced.
- Scan duration and stats are reported.
- `flutter analyze` reports no errors.

