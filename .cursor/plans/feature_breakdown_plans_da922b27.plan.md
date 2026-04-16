---
name: Feature Breakdown Plans
overview: Break the ShadowPlay Toggler project (described in design.md) into ~25 small, independently buildable feature plans, each stored as a markdown file in a plans/ folder.
todos:
  - id: create-plans-dir
    content: Create plans/ directory
    status: completed
  - id: write-foundation
    content: Write plans 01-04 (Foundation)
    status: completed
  - id: write-native-bridge
    content: Write plans 05-11 (Native C/C++ Bridge)
    status: completed
  - id: write-ffi-data
    content: Write plans 12-13 (FFI + Data Layer)
    status: completed
  - id: write-ui-shell
    content: Write plans 14-15 (UI Shell)
    status: completed
  - id: write-ui-lists
    content: Write plans 16-19 (UI Lists)
    status: completed
  - id: write-ui-detail
    content: Write plans 20, 25 (UI Detail)
    status: completed
  - id: write-feature-flows
    content: Write plans 21-24 (Feature Flows)
    status: completed
  - id: write-lifecycle
    content: Write plans 26-30 (Lifecycle & Polish)
    status: completed
isProject: false
---

# Feature Breakdown for ShadowPlay Toggler

The project in `design.md` describes a Flutter Windows desktop app with a native C/C++ NVAPI bridge. The current codebase is just the default Flutter counter template (with a broken `main.dart`). I will create ~25 small plan files in `plans/`, ordered by dependency so subagents can build them roughly in sequence.

## Dependency Graph (simplified)

```mermaid
graph TD
    P01[01 Fix Template] --> P02[02 Project Structure]
    P02 --> P03[03 App Theme]
    P02 --> P04[04 State Management]
    P02 --> P05[05 Native Bridge CMake]
    P05 --> P06[06 Bridge Init/Shutdown]
    P06 --> P07[07 Bridge Session Mgmt]
    P07 --> P08[08 Bridge Enumerate Profiles]
    P07 --> P09[09 Bridge Enumerate Apps]
    P07 --> P10[10 Bridge Get/Set Settings]
    P07 --> P11[11 Bridge Backup/Restore]
    P06 --> P12[12 Dart FFI Bindings]
    P12 --> P08
    P12 --> P09
    P12 --> P10
    P12 --> P11
    P04 --> P13[13 Local Database]
    P03 --> P14[14 App Shell Layout]
    P14 --> P15[15 Left Pane Tabs]
    P15 --> P16[16 Managed Rules List]
    P15 --> P17[17 Detected Rules List]
    P15 --> P18[18 NVIDIA Defaults List]
    P15 --> P19[19 Search/Filter]
    P14 --> P20[20 Rule Detail View]
    P20 --> P25[25 Advanced Hex Editor]
    P12 --> P21[21 Add Program Flow]
    P12 --> P22[22 Remove Exclusion Flow]
    P12 --> P23[23 Scan Profiles Feature]
    P12 --> P24[24 Backup/Restore UI]
    P13 --> P26[26 Startup Reconciliation]
    P26 --> P27[27 Adopt Existing Rules]
    P16 --> P28[28 Batch Operations]
    P14 --> P29[29 Error Handling]
    P29 --> P30[30 First Run Experience]
```



## Plan Files to Create

### Foundation (01-04)

- **01-fix-template-and-setup.md** - Fix broken main.dart, remove counter demo, clean slate
- **02-project-structure.md** - Create lib/ folder structure (models, services, screens, widgets, providers)
- **03-app-theme.md** - Dark charcoal + NVIDIA green theme, typography, button styles
- **04-state-management.md** - Add Riverpod, set up core providers

### Native C/C++ Bridge (05-11)

- **05-native-bridge-cmake-setup.md** - CMake config for shadowplay_bridge.dll, NVAPI SDK integration
- **06-native-bridge-init-shutdown.md** - NvAPI_Initialize / NvAPI_Unload wrapper functions
- **07-native-bridge-session-management.md** - DRS session create/load/save/destroy
- **08-native-bridge-enumerate-profiles.md** - Enumerate all profiles + profile info
- **09-native-bridge-enumerate-apps.md** - Enumerate applications within a profile
- **10-native-bridge-get-set-settings.md** - Get/set/delete/restore DWORD settings
- **11-native-bridge-backup-restore.md** - Export/import DRS settings to/from file

### Dart FFI Layer (12)

- **12-dart-ffi-bindings.md** - All FFI bindings from Dart to the native bridge DLL

### Data Layer (13)

- **13-local-database.md** - SQLite/Hive schema for managed rules, CRUD operations

### UI Shell (14-15)

- **14-app-shell-layout.md** - Two-pane layout scaffold with top toolbar
- **15-left-pane-tabs.md** - Tab bar: Managed / Detected Existing Rules / NVIDIA Defaults

### UI Lists (16-19)

- **16-managed-rules-list.md** - Managed tab: list items with status badges
- **17-detected-rules-list.md** - Detected Existing Rules tab
- **18-nvidia-defaults-list.md** - NVIDIA Defaults tab (collapsed/secondary)
- **19-search-filter.md** - Search bar and filtering across all tabs

### UI Detail (20, 25)

- **20-rule-detail-view.md** - Right pane: app name, profile, status, source badges
- **25-advanced-hex-editor.md** - Raw hex value editor for setting 0x809D5F60

### Feature Flows (21-24)

- **21-add-program-flow.md** - File picker, profile lookup, create/update rule
- **22-remove-exclusion-flow.md** - Restore default / delete managed profile
- **23-scan-profiles-feature.md** - Full DRS scan, populate detected + defaults tabs
- **24-backup-restore-feature.md** - Backup/restore UI + DRS file operations

### Lifecycle & Polish (26-30)

- **26-startup-reconciliation.md** - Reconcile local DB with driver state on launch
- **27-adopt-existing-rules.md** - Adopt unmanaged rules into Managed (post-MVP)
- **28-batch-operations.md** - Batch enable/disable managed rules (post-MVP)
- **29-error-handling-notifications.md** - Snackbars, dialogs, error boundaries
- **30-first-run-experience.md** - Empty state, first-scan prompt, backup offer

