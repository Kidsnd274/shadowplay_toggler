# 15 - Left Pane Tabs

## Goal

Add tab navigation to the left pane with three tabs: Managed, Detected Existing Rules, and NVIDIA Defaults.

## Prerequisites

- Plan 14 (App Shell Layout) completed.

## Design Spec

From `design.md`:
- **Managed** starts empty and is the default tab.
- **Detected Existing Rules** appears after first scan.
- **NVIDIA Defaults** is collapsed or secondary so it does not clutter the main workflow.

## Tasks

1. **Add `TabController` to the left pane**
   - Convert `LeftPane` to a `StatefulWidget` (or use `ConsumerStatefulWidget` for Riverpod).
   - Create a `TabController` with 3 tabs.
   - Use `DefaultTabController` or manual controller.

2. **Create the tab bar**
   - Tabs: "Managed", "Detected", "Defaults"
   - Style with the app theme (NVIDIA green indicator, white text).
   - Tabs should be compact and fit within the left pane width.
   - Use short labels to avoid overflow.

3. **Create tab content placeholders**
   - Each tab shows a `ListView` placeholder.
   - **Managed tab**: Empty state with message "No managed rules yet. Click 'Add Program' to get started."
   - **Detected tab**: Message "Click 'Scan NVIDIA Profiles' to detect existing rules."
   - **Defaults tab**: Message "Click 'Scan NVIDIA Profiles' to view NVIDIA default profiles."

4. **Create `lib/widgets/rule_list_tile.dart`**
   - A reusable list tile widget for displaying a rule in any of the three tabs.
   - Shows:
     - Executable name (primary text, bold)
     - Profile name (secondary text, smaller)
     - Status badge: small colored indicator (green = excluded, grey = default, orange = unknown)
     - Source badge: "Managed" / "External" / "Default"
   - On tap: sets the selected rule provider (from plan 04) to this rule.
   - Selected state: highlighted background.
   - This widget will be used by plans 16-18.

5. **Connect tab selection to state**
   - Create a `selectedTabProvider` in `lib/providers/` to track the active tab.
   - This allows other parts of the UI to know which tab is active.

## Acceptance Criteria

- Three tabs appear in the left pane.
- The "Managed" tab is selected by default.
- Each tab shows its placeholder empty state message.
- `RuleListTile` widget is defined and reusable.
- Tab switching works smoothly with NVIDIA green indicator.
- `flutter analyze` reports no errors.
