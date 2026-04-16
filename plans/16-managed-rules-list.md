# 16 - Managed Rules List

## Goal

Populate the "Managed" tab with the list of user-managed exclusion rules, reading from the local database and live driver state.

## Prerequisites

- Plan 15 (Left Pane Tabs) completed.
- Plan 13 (Local Database) completed.
- Plan 04 (State Management) completed.

## Tasks

1. **Wire up the managed rules provider**
   - Update `lib/providers/managed_rules_provider.dart` to read from `ManagedRulesRepository`.
   - Provider should return a `List<ManagedRule>` from the local database.
   - Use `AsyncNotifierProvider` or `FutureProvider` since DB reads are async.

2. **Build the Managed tab content**
   - Create `lib/widgets/managed_rules_tab.dart`.
   - Watch the `managedRulesProvider`.
   - Show loading indicator while fetching.
   - Show empty state if no rules: centered icon + "No managed rules yet" + "Click 'Add Program' to get started" text.
   - Show a `ListView.builder` of `RuleListTile` widgets when rules exist.

3. **Handle list item selection**
   - On tap, update the `selectedRuleProvider` with the tapped rule.
   - Highlight the selected item (different background color).
   - Only one item can be selected at a time.

4. **Show status indicators on each tile**
   - Each `RuleListTile` in the Managed tab should show:
     - Green dot = exclusion is active and verified in driver
     - Yellow dot = managed rule exists in DB but not yet verified against driver
     - Red dot = rule was in DB but is missing/different in driver (drift detected)
   - To determine status, cross-reference the local DB rule with actual driver state (will need NVAPI service once connected; for now, use a placeholder status).

5. **Support right-click context menu (optional, nice-to-have)**
   - Right-clicking a rule could show: "Remove", "View in Explorer", "Copy path".
   - Use `GestureDetector` with `onSecondaryTapUp`.

6. **Connect to the left pane**
   - Replace the Managed tab placeholder from plan 15 with `ManagedRulesTab`.

## Acceptance Criteria

- Managed tab shows rules from the local database.
- Empty state is shown when no rules exist.
- Tapping a rule selects it and updates the right pane provider.
- Status indicators show the correct color based on rule state.
- List scrolls if many rules exist.
- `flutter analyze` reports no errors.
