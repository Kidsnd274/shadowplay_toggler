# 22 - Remove Exclusion Flow

## Goal

Implement the flow for removing/disabling an exclusion rule safely by clearing the setting override on the associated NVIDIA profile. The app never deletes profiles or removes application attachments; an empty profile is a no-op under NVIDIA's hierarchy and leaving it in place keeps future re-exclusion cheap.

## Prerequisites

- Plan 12 (Dart FFI Bindings) completed.
- Plan 13 (Local Database) completed.
- Plan 20 (Rule Detail View) completed (action buttons exist).

## Background

From `design.md`:
- Do NOT assume `0x00000000` means "off" — the value is undocumented.
- Do NOT delete profiles or remove application attachments — that's destructive and unnecessary.
- The branch we take depends on whether the profile is user-created or predefined, which we learn from the live DRS setting metadata (`NVDRS_SETTING.isPredefinedValid`) rather than from our own authorship claim.

## Tasks

1. **Create `lib/services/remove_exclusion_service.dart`**
   - Orchestrates the removal flow.
   - Method:
     ```dart
     Future<RemoveResult> removeExclusion(ManagedRule rule);
     ```
   - Logic:
     1. Look up the profile and the current setting via the native bridge.
     2. Reset the `0x809D5F60` override on that profile:
        - If the setting has a predefined value for this profile (NVIDIA-predefined profile): call `NvAPI_DRS_RestoreProfileDefaultSetting` to restore NVIDIA's original value.
        - Otherwise (user-created profile or predefined profile where the setting was purely our override): call `NvAPI_DRS_DeleteSetting` to remove the setting key entirely.
     3. Save settings.
     4. Remove the rule from the local database.
     5. Return result. **Do not delete the profile and do not detach the application.**

2. **Create `lib/models/remove_result.dart`**
   ```dart
   class RemoveResult {
     final bool success;
     final String? errorMessage;
     final String action; // 'setting_deleted', 'setting_restored'
   }
   ```

3. **Wire up the "Remove Exclusion" / toggle button**
   - In the rule detail view, the primary toggle should call this service when turning off an exclusion.
   - Show a confirmation dialog before removing:
     - "Remove the capture exclusion for {exeName}?"
     - Short explanation: "The setting override will be cleared. The NVIDIA profile itself will be left in place so this exe can be re-excluded quickly later."
     - [Remove] [Cancel]

4. **Wire up the "Restore Default" button**
   - The "Restore Default" button in the detail view calls the same service but leaves the rule row in the local DB (so the user can re-enable without re-picking the exe).
   - This is effectively the same NVAPI operation; the difference is purely UI state: "Remove Exclusion" deletes the managed-list row, "Restore Default" keeps it (the row will show as drifted on next scan).

5. **Refresh state after removal**
   - Invalidate `managedRulesProvider` so the list updates.
   - Clear `selectedRuleProvider` if the removed rule was selected.
   - Show a success snackbar: "Exclusion removed for {exeName}."

6. **Handle errors**
   - NVAPI call fails: show error, do NOT remove from local DB (state would be inconsistent).
   - Profile not found in driver: remove from local DB anyway (stale entry), show an informational message.

## Acceptance Criteria

- Removing a rule clears the `0x809D5F60` override on its profile and saves.
- The profile and its application attachment are left intact; no profiles are deleted.
- The local database is updated after successful removal.
- A confirmation dialog is shown before any destructive action.
- The managed list refreshes after removal.
- Error cases are handled gracefully.
- `flutter analyze` reports no errors.
