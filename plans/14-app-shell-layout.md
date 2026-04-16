# 14 - App Shell Layout

## Goal

Build the main two-pane layout scaffold with a top toolbar, matching the design document's wireframe.

## Prerequisites

- Plan 03 (App Theme) completed.
- Plan 04 (State Management) completed.

## Reference Layout from design.md

```
+------------------------------------------------------------------+
| Capture Exclusion Manager                                         |
| [Scan NVIDIA Profiles] [Add Program] [Backup] [Settings]         |
+------------------------------+-----------------------------------+
| Left Pane                    | Right Pane                        |
| (tabs + list)                | (detail view)                     |
|                              |                                   |
|                              |                                   |
|                              |                                   |
+------------------------------+-----------------------------------+
```

## Tasks

1. **Replace placeholder `HomeScreen` with the real layout**
   - Edit `lib/screens/home_screen.dart`.
   - Use a `Column` with:
     - Top: Toolbar row
     - Bottom: Expanded `Row` with left pane and right pane

2. **Build the toolbar**
   - Create `lib/widgets/app_toolbar.dart`.
   - Contains a `Row` of action buttons:
     - **Scan NVIDIA Profiles** - `ElevatedButton` or `OutlinedButton` with scan icon
     - **Add Program** - `ElevatedButton` with add icon (primary action, NVIDIA green)
     - **Backup** - `OutlinedButton` with save/backup icon
     - **Settings** - `IconButton` with gear icon
   - Toolbar has the app title "Capture Exclusion Manager" on the left.
   - Buttons are on the right side of the toolbar.
   - Toolbar has a bottom border or subtle separator.

3. **Build the left pane placeholder**
   - Create `lib/widgets/left_pane.dart`.
   - Fixed width (e.g., 300px) or flexible with `Flexible(flex: 1)`.
   - Has a slightly lighter background (graphite panel color).
   - Has a visible right border.
   - Content: placeholder `Center(child: Text('Left Pane'))`.
   - Will be populated with tabs in plan 15.

4. **Build the right pane placeholder**
   - Create `lib/widgets/right_pane.dart`.
   - Takes remaining space with `Flexible(flex: 2)` or `Expanded`.
   - Content: placeholder showing "Select a rule to view details" centered text.
   - Will be populated with the detail view in plan 20.

5. **Add a vertical divider between panes**
   - Use a `VerticalDivider` or a thin `Container` with border.
   - Optionally make the divider draggable for resizable panes (nice-to-have, not required).

6. **Handle window sizing**
   - The app should look good at its default 1280x720 size.
   - Left pane should have a minimum width.
   - Right pane should stretch to fill remaining space.

7. **Wire up toolbar button callbacks**
   - For now, buttons should print to console or show a `SnackBar` saying "Not implemented yet".
   - The actual functionality will be connected in plans 21-24.

## Acceptance Criteria

- The app shows a toolbar at the top with the four action buttons.
- Below the toolbar, a two-pane layout fills the remaining space.
- Left pane has a fixed or proportional width with a visible border.
- Right pane shows a placeholder "select a rule" message.
- The layout matches the wireframe from the design doc.
- The NVIDIA dark theme is visible (charcoal background, green accent buttons).
- `flutter analyze` reports no errors.
