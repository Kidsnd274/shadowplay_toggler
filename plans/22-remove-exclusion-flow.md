# 22 - Remove Exclusion Flow

## Goal

Implement the flow for removing/disabling an exclusion rule safely, following the design doc's guidance on restoring defaults rather than forcing zero values.

## Prerequisites

- Plan 12 (Dart FFI Bindings) completed.
- Plan 13 (Local Database) completed.
- Plan 20 (Rule Detail View) completed (action buttons exist).

## Background

From `design.md`, the safest "off" action is:
- If the app created the profile: remove the app / delete the profile if empty.
- If the app modified an existing profile: restore the setting to default.
- Do NOT assume `0x00000000` means "off" since the value is undocumented.

## Tasks

1. **Create `lib/services/remove_exclusion_service.dart`**
   - Orchestrates the removal flow.
   - Method:
     ```dart
     Future<RemoveResult> removeExclusion(ManagedRule rule);
     ```
   - Logic:
     1. Check `rule.profileWasCreated`:
        - If true (app created this profile):
          a. Delete the setting from the profile.
          b. Remove the application from the profile.
          c. If the profile is now empty, delete the profile entirely.
          d. Save settings.
        - If false (app modified an existing profile):
          a. Restore the setting to its default value using `NvAPI_DRS_RestoreProfileDefaultSetting`.
          b. Save settings.
     2. Remove the rule from the local database.
     3. Return result.

2. **Create `lib/models/remove_result.dart`**
   ```dart
   class RemoveResult {
     final bool success;
     final String? errorMessage;
     final String action; // 'profile_deleted', 'setting_restored', 'setting_deleted'
   }
   ```

3. **Wire up the "Remove Exclusion" / toggle button**
   - In the rule detail view, the primary toggle should call this service when turning off an exclusion.
   - Show a confirmation dialog before removing:
     - "Remove the capture exclusion for {exeName}?"
     - Explain what will happen (profile deleted vs setting restored).
     - [Remove] [Cancel]

4. **Wire up the "Restore Default" button**
   - The "Restore Default" button in the detail view should call the restore path.
   - Show a confirmation dialog.

5. **Refresh state after removal**
   - Invalidate `managedRulesProvider` to remove the rule from the list.
   - Clear `selectedRuleProvider` if the removed rule was selected.
   - Show a success snackbar: "Exclusion removed for {exeName}."

6. **Handle errors**
   - NVAPI call fails: show error, do NOT remove from local DB (state would be inconsistent).
   - Profile not found in driver: remove from local DB anyway (stale entry), show info message.

## Acceptance Criteria

- Removing an app-created profile deletes the profile entirely.
- Removing from a pre-existing profile restores the setting to default.
- Local database is updated after successful removal.
- Confirmation dialog is shown before any destructive action.
- The managed list refreshes after removal.
- Error cases are handled gracefully.
- `flutter analyze` reports no errors.
