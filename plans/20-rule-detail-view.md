# 20 - Rule Detail View

## Goal

Build the right pane detail view that shows comprehensive information about the selected rule and provides primary actions.

## Prerequisites

- Plan 14 (App Shell Layout) completed.
- Plan 04 (State Management) completed (selectedRuleProvider defined).

## Reference Layout from design.md

```
+-----------------------------------+
| App: obs64.exe                    |
| Profile: obs64.exe                |
| Status: Excluded                  |
|                                   |
| [ Exclude from Overlay ]          |
|                                   |
| Setting ID: 0x809D5F60           |
| Current Value: 0x10000000        |
| Source: User Override             |
|                                   |
| [Restore Default] [Advanced]      |
+-----------------------------------+
```

## Tasks

1. **Create `lib/widgets/right_pane.dart` (or update existing)**
   - Watch the `selectedRuleProvider`.
   - If no rule is selected, show the empty state: centered icon + "Select a rule to view details".
   - If a rule is selected, show the detail view.

2. **Build the detail view layout**
   - Create `lib/widgets/rule_detail_view.dart`.
   - Takes an `ExclusionRule` as input.
   - Sections from top to bottom:

   **Header section:**
   - App icon (extracted from the exe if possible, or a default app icon).
   - Executable name (large, bold).
   - Full executable path (smaller, grey, selectable/copyable).

   **Profile section:**
   - Profile name with a badge indicating source type.
   - Source badges with colors:
     - "Managed" = NVIDIA green
     - "External" = orange/amber
     - "NVIDIA Default" = grey
     - "Inherited" = blue-grey

   **Status section:**
   - Status display: "Excluded" (green) or "Not Excluded" (grey) or "Unknown Value" (amber).
   - Current hex value displayed.

   **Primary action:**
   - Large toggle button: "Exclude from Overlay" / "Remove Exclusion"
   - Green when exclusion is active, outlined/grey when not active.
   - This is the main user action.

   **Details section:**
   - Setting ID: `0x809D5F60` (monospace, copyable)
   - Current Value: `0x10000000` (monospace, copyable)
   - Predefined Value: displayed if different from current
   - Source: "User Override" / "Predefined" / "Inherited from Global"

   **Action buttons:**
   - "Restore Default" - outlined button, caution style
   - "Advanced" - text button, opens advanced editor (plan 25)

3. **Handle different rule source types**
   - **Managed rules**: show all actions (toggle, restore, advanced).
   - **Detected/external rules**: show an "Adopt" button instead of toggle. Show "This rule was not created by this app."
   - **NVIDIA defaults**: read-only view. No action buttons. Show "This is a predefined NVIDIA profile."

4. **Style the detail view**
   - Use the app theme's graphite card backgrounds for sections.
   - Visible borders between sections.
   - Consistent padding and spacing.
   - Monospace font for hex values and setting IDs.

5. **Wire up action button callbacks**
   - For now, buttons can show "Not implemented" snackbar or log to console.
   - Actual functionality will be connected in plans 21-22.

6. **Add a "restart target app" notice**
   - Below the primary action, show a subtle info banner: "Restart the target app for changes to fully apply."
   - Only show when a change has just been made (use a local state flag).

## Acceptance Criteria

- Right pane shows "Select a rule" when nothing is selected.
- Selecting a rule in the left pane shows its full details in the right pane.
- All information sections (header, profile, status, details) are displayed.
- Source type badges are color-coded correctly.
- Action buttons are visible and correctly shown/hidden based on rule type.
- Hex values are displayed in monospace font.
- `flutter analyze` reports no errors.
