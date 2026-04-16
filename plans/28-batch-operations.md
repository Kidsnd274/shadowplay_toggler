# 28 - Batch Operations (Post-MVP)

## Goal

Enable batch enable/disable of managed exclusion rules.

## Prerequisites

- Plan 16 (Managed Rules List) completed.
- Plan 21 (Add Program Flow) completed.
- Plan 22 (Remove Exclusion Flow) completed.

## Background

From `design.md` post-MVP features: "Batch enable/disable managed rules." This is useful for users who want to temporarily disable all exclusions (e.g., when recording gameplay) and re-enable them later.

## Tasks

1. **Add multi-select mode to the managed list**
   - Create a `multiSelectProvider` in `lib/providers/`:
     ```dart
     final multiSelectModeProvider = StateProvider<bool>((ref) => false);
     final selectedRuleIdsProvider = StateProvider<Set<int>>((ref) => {});
     ```
   - When multi-select is active:
     - Show checkboxes on each list tile.
     - Tapping a tile toggles its selection instead of showing details.
     - Show a "Select All" / "Deselect All" option.

2. **Add a batch action bar**
   - Create `lib/widgets/batch_action_bar.dart`.
   - Appears at the bottom of the left pane (or replaces the toolbar) when multi-select is active.
   - Shows:
     - "{N} rules selected"
     - [Enable All] - applies exclusion to all selected rules
     - [Disable All] - removes exclusion from all selected rules
     - [Cancel] - exits multi-select mode

3. **Trigger multi-select mode**
   - Long-press on a list tile enters multi-select mode.
   - Or add a "Select" button in the managed tab header.
   - Pressing Escape or Cancel exits multi-select mode.

4. **Implement batch operations**
   - Create `lib/services/batch_service.dart`:
     ```dart
     Future<BatchResult> batchEnable(List<ManagedRule> rules);
     Future<BatchResult> batchDisable(List<ManagedRule> rules);
     ```
   - For batch enable: apply exclusion setting to each rule's profile.
   - For batch disable: restore default for each rule's profile.
   - Open a single NVAPI session, make all changes, save once at the end.
   - Track individual successes/failures.

5. **Create `lib/models/batch_result.dart`**
   ```dart
   class BatchResult {
     final int total;
     final int succeeded;
     final int failed;
     final List<String> errors;
   }
   ```

6. **Show batch operation progress and results**
   - Progress dialog while batch is running.
   - Summary after completion: "Enabled X of Y rules. Z failures."
   - If any failures, list them.

7. **Refresh state after batch**
   - Invalidate `managedRulesProvider`.
   - Exit multi-select mode.
   - Clear selection.

## Acceptance Criteria

- Users can enter multi-select mode and select multiple rules.
- Batch enable applies exclusion to all selected rules.
- Batch disable restores defaults for all selected rules.
- Progress and results are shown.
- Individual failures don't block the rest of the batch.
- `flutter analyze` reports no errors.
