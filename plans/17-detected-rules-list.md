# 17 - Detected Existing Rules List

## Goal

Populate the "Detected" tab with rules found by scanning the NVIDIA DRS database that are NOT managed by this app.

## Prerequisites

- Plan 15 (Left Pane Tabs) completed.
- Plan 04 (State Management) completed.

## Background

"Detected Existing Rules" are driver profile entries where setting `0x809D5F60` has a user override, but the `(exePath, profileName)` pair is not in the app's local SQLite database. These could have been set by NVIDIA Profile Inspector, other tools, manual editing, or by this app itself before a local-DB loss (in which case the user can re-adopt them).

## Tasks

1. **Wire up the detected rules provider**
   - Update `lib/providers/detected_rules_provider.dart`.
   - This provider should store rules discovered during a scan.
   - Use a `StateNotifierProvider` or `NotifierProvider` that starts empty and gets populated when a scan is performed.

2. **Create the detected rules model**
   - Detected rules use the same `ExclusionRule` model but with `sourceType: 'external'`.
   - They should include:
     - Executable name and path (if available)
     - Profile name
     - Current setting value
     - Whether the profile is predefined
     - Whether the setting value is the known exclusion value or an unknown value

3. **Build the Detected tab content**
   - Create `lib/widgets/detected_rules_tab.dart`.
   - Watch the `detectedRulesProvider`.
   - Show pre-scan state: "Click 'Scan NVIDIA Profiles' to detect existing rules." with a scan button.
   - Show empty post-scan state: "No external exclusion rules found." after a scan completes with no results.
   - Show list of `RuleListTile` widgets when rules are found.

4. **Differentiate from managed rules visually**
   - Detected rules should have a different source badge: "External" instead of "Managed".
   - Use a slightly different accent color or icon to distinguish them.
   - Show an "Adopt" action hint (small text or icon) suggesting the user can adopt the rule.

5. **Handle list item selection**
   - Same behavior as Managed tab: tapping sets `selectedRuleProvider`.
   - The right pane detail view should show an "Adopt this rule" option for detected rules.

6. **Connect to the left pane**
   - Replace the Detected tab placeholder from plan 15 with `DetectedRulesTab`.

## Acceptance Criteria

- Detected tab shows pre-scan empty state on first launch.
- After a scan, detected external rules are listed.
- Rules are visually distinguished from managed rules.
- Tapping a rule selects it for the detail view.
- `flutter analyze` reports no errors.
