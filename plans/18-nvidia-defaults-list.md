# 18 - NVIDIA Defaults List

## Goal

Populate the "Defaults" tab with NVIDIA's predefined profiles that have the capture exclusion setting.

## Prerequisites

- Plan 15 (Left Pane Tabs) completed.
- Plan 04 (State Management) completed.

## Background

NVIDIA ships predefined profiles with the driver. Some may have predefined values for setting `0x809D5F60`. These are read-only from the app's perspective - users should not be modifying NVIDIA's own defaults. This tab is informational, showing what NVIDIA has already configured.

## Tasks

1. **Create a defaults provider**
   - Create `lib/providers/nvidia_defaults_provider.dart`.
   - Stores predefined rules discovered during a scan.
   - Use a `StateNotifierProvider` that starts empty.

2. **Build the Defaults tab content**
   - Create `lib/widgets/nvidia_defaults_tab.dart`.
   - Watch the `nvidiaDefaultsProvider`.
   - Show pre-scan state: "Click 'Scan NVIDIA Profiles' to view NVIDIA default profiles."
   - Show the list of predefined profiles that have the target setting.
   - Each item shows:
     - Profile name
     - Associated app name(s)
     - Predefined value (hex)
     - "NVIDIA Default" badge

3. **Make the tab secondary/collapsed by default**
   - Per the design doc, this tab should not clutter the main workflow.
   - Consider showing a count badge on the tab label: "Defaults (42)".
   - The list should be read-only - no toggle, no modify actions.

4. **Handle list item selection**
   - Tapping a default rule shows its details in the right pane.
   - The detail view should clearly indicate this is a read-only NVIDIA default.
   - No modify/delete actions should be available for defaults.

5. **Visual styling**
   - Use a muted/dimmer style compared to Managed and Detected tabs.
   - Badge color: grey or blue-grey for "NVIDIA Default".
   - List items should feel informational, not actionable.

6. **Connect to the left pane**
   - Replace the Defaults tab placeholder from plan 15 with `NvidiaDefaultsTab`.

## Acceptance Criteria

- Defaults tab shows pre-scan empty state initially.
- After a scan, NVIDIA predefined profiles with the target setting are listed.
- Items are clearly marked as read-only NVIDIA defaults.
- No modify/delete actions are available for default rules.
- Tab count badge shows the number of defaults found.
- `flutter analyze` reports no errors.
