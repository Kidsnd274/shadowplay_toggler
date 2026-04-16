# ShadowPlay Toggler

A focused Windows desktop utility for managing **per-application NVIDIA capture
exclusions** (Instant Replay / ShadowPlay / Overlay) by editing the underlying
NVIDIA Driver Settings (DRS) profiles through NVAPI.

---

## Table of contents

- [What it does](#what-it-does)
- [Platform requirements](#platform-requirements)
- [Repository architecture](#repository-architecture)
- [Functionality overview](#functionality-overview)
- [What "reconciliation" means](#what-reconciliation-means)
- [Getting started (development)](#getting-started-development)
- [Adding a feature](#adding-a-feature)
- [Updating the NVAPI SDK submodule](#updating-the-nvapi-sdk-submodule)
- [License & contributing](#license--contributing)

---

## What it does

NVIDIA's overlay/capture stack sometimes treats normal desktop applications
(SignalRGB, OBS, Paint.NET, etc.) as if they were games. The official
workaround is to edit an undocumented DRS setting (`0x809D5F60`) through tools
like NVIDIA Profile Inspector — error-prone and easy to lose track of.

ShadowPlay Toggler gives you:

- A clean **Managed** list of per-app exclusions you've added.
- A **Detected Existing Rules** view of overrides already on the driver that
  this app didn't create (so you can adopt them).
- A **NVIDIA Defaults** view of predefined NVIDIA profiles that already carry
  the setting, for reference.
- Safe rollback (delete-setting / restore-default rather than guessing an
  "off" value), startup reconciliation against the driver, and full DRS
  backup/import via the NVAPI save/load APIs.

The full design is in [`design.md`](design.md).

## Platform requirements

- **Windows 10 or newer** (NVAPI is Windows-only).
- **NVIDIA GPU** with a current NVIDIA driver installed (the driver provides
  the NVAPI runtime; this repo only ships the headers + import library).
- Flutter SDK `^3.11.1` (see [`pubspec.yaml`](pubspec.yaml)).
- A C++17-capable MSVC toolchain — `flutter run -d windows` will use whatever
  Visual Studio Build Tools you have configured for Flutter desktop.
- CMake 3.14+ (bundled with recent Visual Studio installs).

## Repository architecture

```
shadowplay_toggler/
├── lib/                       # Flutter app (Dart)
│   ├── main.dart              # Entry point + global error handlers
│   ├── app.dart               # MaterialApp + theme
│   ├── screens/               # Top-level screens
│   ├── widgets/               # UI components (left/right pane, dialogs, …)
│   ├── providers/             # Riverpod providers (state wiring)
│   ├── services/              # Business logic (scan, reconcile, backup, …)
│   ├── models/                # Plain-data DTOs
│   ├── constants/             # Theme, setting IDs, status enums
│   └── native/
│       └── bridge_ffi.dart    # dart:ffi bindings for shadowplay_bridge.dll
├── native/                    # C++ native bridge
│   ├── CMakeLists.txt         # Builds shadowplay_bridge.dll
│   ├── bridge.h               # Public C ABI consumed by Dart FFI
│   ├── bridge.cpp             # NVAPI integration
│   └── nvapi_sdk/             # NVAPI SDK (git submodule, see below)
├── windows/                   # Flutter Windows runner (auto-generated + tweaks)
├── plans/                     # Per-feature implementation plans
├── test/                      # Dart tests
├── design.md                  # Long-form design doc
└── pubspec.yaml
```

The runtime data flow:

```
Flutter UI (Dart)
      │   Riverpod providers
      ▼
Services (scan_service, reconciliation_service, backup_service, …)
      │
      ▼
bridge_ffi.dart  ── dart:ffi ──▶  shadowplay_bridge.dll
                                          │
                                          ▼
                                  NVAPI (nvapi64.lib + driver)
                                          │
                                          ▼
                                  NVIDIA DRS profiles / settings
```

Two **sources of truth** coexist:

| Source              | Owns                                     | Where it lives                               |
| ------------------- | ---------------------------------------- | -------------------------------------------- |
| NVIDIA driver (DRS) | Current effective profile/setting state  | The driver's own database                    |
| Local SQLite DB     | User intent for app-managed rules        | App data dir (via `path_provider` + sqflite) |

The local DB only stores *managed* metadata (exe path, intended value,
previous state, timestamps). The driver is always re-queried for current
state — see [reconciliation](#what-reconciliation-means).

### Native bridge surface

`native/bridge.h` exposes a small, stable C ABI. Highlights:

- **Lifecycle:** `bridge_initialize`, `bridge_shutdown`, `bridge_is_initialized`
- **DRS session:** `bridge_create_session`, `bridge_load_settings`,
  `bridge_save_settings`, `bridge_destroy_session`, `bridge_open_session`
- **Enumeration:** `bridge_get_all_profiles_json`,
  `bridge_get_profile_apps_json`, `bridge_find_application`,
  `bridge_get_base_profile_apps_json`
- **Settings:** `bridge_get_setting`, `bridge_set_dword_setting`,
  `bridge_delete_setting`, `bridge_restore_setting_default`,
  `bridge_create_profile`, `bridge_add_application`,
  `bridge_apply_exclusion`, `bridge_clear_exclusion`,
  `bridge_delete_profile`
- **Scan:** `bridge_scan_exclusion_rules` (single-crossing full DRS walk)
- **Backup:** `bridge_export_settings`, `bridge_import_settings`,
  `bridge_get_default_backup_path`

Functions returning `const char*` JSON allocate on the heap; the caller
**must** free them via `bridge_free_json`. Two functions
(`bridge_get_error_message`, `bridge_get_default_backup_path`) return
pointers into static buffers and **must not** be freed.

## Functionality overview

| Feature                  | Where                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| Add program to exclusion | `lib/services/add_program_service.dart` → `bridge_apply_exclusion`                       |
| Remove exclusion         | `lib/services/remove_exclusion_service.dart` → `bridge_clear_exclusion`                  |
| Adopt detected rule      | `lib/services/adopt_rule_service.dart`                                                   |
| Batch enable/disable     | `lib/services/batch_service.dart`                                                        |
| Full DRS scan            | `lib/services/scan_service.dart` → `bridge_scan_exclusion_rules` (runs on a Dart isolate) |
| Startup reconciliation   | `lib/services/reconciliation_service.dart`                                               |
| Backup / restore         | `lib/services/backup_service.dart` → `bridge_export_settings` / `bridge_import_settings` |
| Local persistence        | `lib/services/database_service.dart` (sqflite_common_ffi)                                |
| Rules export             | `lib/services/rules_export_service.dart`                                                 |
| Notifications / errors   | `lib/services/notification_service.dart` + `lib/widgets/error_*` / `app_snackbar.dart`   |

## What "reconciliation" means

**Reconciliation** is the startup pass that compares two pictures of the
world and reclassifies every managed rule accordingly:

1. **Local DB** — what *we* think is excluded (rows in the `managed_rules`
   table, each with an exe path and intended setting value).
2. **Driver state** — what NVAPI currently reports for the capture-exclusion
   setting (`0x809D5F60`) across every profile, fetched in a single DRS
   walk via `bridge_scan_exclusion_rules`.

The orchestrator is
[`ReconciliationService`](lib/services/reconciliation_service.dart). It
delegates the heavy DRS walk to `ScanService` (which runs on a background
isolate) and then layers two extra responsibilities on top:

### 1. DRS-reset detection

We persist a deterministic FNV-1a hash of the scan result
(`drs_profile_hash`) in the `app_state` table. If the hash on this run
differs *and* there was a previous hash, we treat it as a likely **driver
reinstall / repair / DRS reset**: every managed rule is flagged
`needsReapply` and the user is invited to push their rules back onto the
driver.

### 2. Per-rule sync status

When no DRS reset is detected, every managed rule is bucketed into one of:

| Status         | Meaning                                                                                                              |
| -------------- | -------------------------------------------------------------------------------------------------------------------- |
| `inSync`       | Profile exists, app is attached, setting value matches our intended value. The happy path.                           |
| `drifted`      | Profile + app still attached, but the setting value was edited (likely by another tool such as Profile Inspector).   |
| `orphaned`     | Profile is gone or the app is no longer attached. The local row is preserved so the user can decide what to do next. |
| `needsReapply` | A DRS reset was detected; the driver no longer carries our setting.                                                  |

Statuses are returned as a `Map<exePath, ManagedRuleSyncStatus>` inside a
[`ReconciliationResult`](lib/models/reconciliation_result.dart). The UI
joins this against `managedRulesProvider` to render per-row status dots and,
when `hasAnyIssue` is true, surfaces the
[`ReconciliationBanner`](lib/widgets/reconciliation_banner.dart).

### Why we need it

- The driver DB is the source of truth for *what is happening right now*,
  but the user's *intent* lives in our local DB.
- DRS profiles can be edited by other tools, wiped by driver reinstalls, or
  repaired by NVIDIA. We must notice and explain these cases instead of
  silently re-writing the user's settings.
- We deliberately do **not** embed ownership markers in profile names or
  settings, because NVAPI does not give us a safe metadata field. Instead,
  reconciliation + the user-driven *adopt* flow recovers state when the
  local DB is lost.

## Getting started (development)

### 1. Clone with submodules

```powershell
git clone https://github.com/<your-fork>/shadowplay_toggler.git
cd shadowplay_toggler
git submodule update --init --recursive
```

If you already cloned without `--recursive`, just run the second command on
its own.

> **Heads-up:** the `.gitmodules` entry currently uses Windows-style
> backslashes in `path`. On a fresh clone Git will still create the working
> tree under `native/nvapi_sdk/`, but `git submodule status` may not list
> it until you've run `git submodule update --init` at least once.

### 2. Verify Flutter is set up for Windows desktop

```powershell
flutter doctor
flutter config --enable-windows-desktop
```

Make sure the Visual Studio toolchain row in `flutter doctor` is green.

### 3. Install Dart dependencies

```powershell
flutter pub get
```

### 4. Build & run

```powershell
flutter run -d windows
```

This drives CMake through the Windows runner, which compiles
`native/bridge.cpp` against the headers in `native/nvapi_sdk/` and links
`native/nvapi_sdk/amd64/nvapi64.lib` to produce `shadowplay_bridge.dll`.
Dart loads that DLL at startup via
[`bridge_ffi.dart`](lib/native/bridge_ffi.dart).

### 5. Run the tests

```powershell
flutter test
```

### Common build issues

- **`shadowplay_bridge.dll` not found at runtime** — usually means CMake
  didn't pick up the new bridge sources. Run `flutter clean && flutter pub
  get && flutter run -d windows`.
- **Linker errors mentioning `NvAPI_*`** — the NVAPI submodule probably
  isn't checked out, or `amd64/nvapi64.lib` is missing. Run
  `git submodule update --init`.
- **NVAPI returns "library not found" at startup** — the user's machine
  doesn't have an NVIDIA driver installed; the app will surface the error
  via `NotificationService` and fall back to read-only behaviour.

## Adding a feature

The repo follows a "plan first, then implement" workflow. Existing plans
live in [`plans/`](plans) and are numbered (e.g.
`26-startup-reconciliation.md`).

A typical loop:

1. **Write a plan** under `plans/NN-short-name.md`. Cover scope,
   user-visible behaviour, native bridge changes (if any), data-model
   changes, error handling, and testing.
2. **Touch the native bridge first** if the feature needs new NVAPI calls:
   - Add the C ABI in `native/bridge.h` (extern "C", `BRIDGE_API`).
   - Implement in `native/bridge.cpp`. Anything returning JSON must be
     allocated such that it can be freed via `bridge_free_json`.
   - Mirror the binding in `lib/native/bridge_ffi.dart`.
3. **Add a service** under `lib/services/` that owns the workflow.
   Services should be unit-testable without Flutter.
4. **Add (or extend) a Riverpod provider** under `lib/providers/` to wire
   the service into the UI.
5. **Build the UI** under `lib/widgets/` (or a new screen under
   `lib/screens/`). Reuse existing primitives (`RuleListTile`,
   `ConfirmationDialog`, `AppSnackbar`, …) where possible.
6. **Persistence** — if you need to read or write local state, go through
   `DatabaseService` and add a repository under `lib/services/` (e.g.
   `managed_rules_repository.dart`). Don't hit sqflite directly from
   widgets.
7. **Tests** — add unit tests under `test/` for new services and any tricky
   widget logic. Mock the bridge through `NvapiService`.
8. **Manual smoke test** — run `flutter run -d windows`, exercise the
   feature, then confirm startup reconciliation still passes.

### Coding conventions

- Lints come from `flutter_lints` (see `analysis_options.yaml`); fix
  warnings before sending a PR.
- Keep the native bridge ABI **append-only** — add new functions rather
  than changing signatures. The DLL is loaded by exact symbol name.
- All NVAPI calls happen on the main thread inside the DLL. DRS scans run
  on a Dart isolate (see `ScanService`); never block the UI thread on
  NVAPI.
- JSON returned from the bridge is documented inline above each function in
  `bridge.h`. Update the comment when you change the shape.

## Updating the NVAPI SDK submodule

The NVAPI SDK is wired in as a git submodule:

```ini
# .gitmodules
[submodule "native/nvapi_sdk"]
    path  = native/nvapi_sdk
    url   = https://github.com/NVIDIA/nvapi
```

NVIDIA publishes new SDK drops periodically (the upstream repo mirrors what
ships on the developer portal). To pull a newer version into this repo:

### 1. Make sure the submodule is initialized

```powershell
git submodule update --init --recursive
```

### 2. Fast-forward the submodule to a newer commit

```powershell
cd native/nvapi_sdk
git fetch origin
git checkout main          # or the tag/branch you want, e.g. R555
git pull --ff-only
cd ../..
```

If you want a *specific* tagged release instead of the tip of `main`, list
tags first:

```powershell
git -C native/nvapi_sdk tag --list | sort
git -C native/nvapi_sdk checkout <tag>
```

### 3. Sanity-check the files the bridge actually uses

After the checkout, confirm these still exist (paths relative to
`native/nvapi_sdk/`):

- `nvapi.h`
- `nvapi_lite_common.h`
- `NvApiDriverSettings.h`
- `NvApiDriverSettings.c`
- `nvapi_interface.h`
- `amd64/nvapi64.lib`
- `License.txt`

If NVIDIA reorganized the layout, update `native/CMakeLists.txt`
(`target_include_directories` and `target_link_libraries`) to match.

### 4. Rebuild the native bridge

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

NVAPI's ABI is generally stable across driver versions, but occasional
struct revisions happen. If linking fails, the symbol named in the linker
error tells you which `NVAPI_INTERFACE` entry in `nvapi_interface.h`
changed.

### 5. Smoke-test the app

Verify that:

- Startup reconciliation completes without a fatal error.
- "Add Program" → exclusion round-trip still works.
- A full DRS scan returns the expected counts.

### 6. Commit the bump

The parent repo records the submodule by commit SHA, so the only diff in
the parent is the gitlink update:

```powershell
git add native/nvapi_sdk
git commit -m "Update NVAPI SDK submodule to R<version>"
```

Keep this in a **dedicated commit** so it's easy to review and revert.

### Notes

- **Do not edit files inside `native/nvapi_sdk/` in place.** They are owned
  by the upstream submodule and any local edits will be wiped on the next
  `git submodule update`.
- The capture-exclusion setting we rely on (`0x809D5F60`,
  value `0x10000000`) is **not** documented in the SDK. It is
  community-identified, so always re-test the exclusion round-trip after a
  bump.

## License & contributing

- The **NVAPI SDK** files under `native/nvapi_sdk/` are © NVIDIA and
  licensed per [`native/nvapi_sdk/License.txt`](native/nvapi_sdk/License.txt).
  They are vendored read-only via the git submodule.
- The **rest of this repository** (Flutter app, native bridge,
  documentation) is part of ShadowPlay Toggler.

For project bugs, comments, and feature requests, open an issue in the
parent repository. Bug reports against NVAPI itself should go to the
[NVAPI Developer Forum](https://forums.developer.nvidia.com/c/developer-tools/other-tools/nvapi/).
