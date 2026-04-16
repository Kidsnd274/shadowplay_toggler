# 21 - Add Program Flow

## Goal

Implement the full "Add Program" user flow: file picker, profile lookup, profile creation or update, and adding the rule to the managed list.

## Prerequisites

- Plan 12 (Dart FFI Bindings) completed.
- Plan 13 (Local Database) completed.
- Plan 14 (App Shell Layout) completed (toolbar "Add Program" button exists).
- Plan 16 (Managed Rules List) completed.

## Background

From `design.md`, the Add Program flow is:
1. User clicks "Add Program"
2. File picker chooses an .exe
3. App resolves full path and calls FindApplicationByName
4. If it already belongs to a profile: show message, let user apply exclusion to existing profile
5. If not found: create a dedicated user profile, add executable, apply setting
6. Add rule to Managed list

## Tasks

1. **Add file picker dependency**
   - Add `file_picker` (latest) to `pubspec.yaml`.
   - This supports Windows native file picker dialogs.

2. **Create `lib/services/add_program_service.dart`**
   - Orchestrates the full add-program flow.
   - Methods:
     ```dart
     Future<AddProgramResult> addProgram(String exePath);
     ```
   - Logic:
     1. Validate the file exists and is an .exe.
     2. Extract the executable name from the path.
     3. Call `nvapiService.findApplication(exePath)` to check if it's already in a profile.
     4. If found in an existing profile:
        - Return result indicating the exe belongs to profile X.
        - Include whether the exclusion setting is already applied.
     5. If not found:
        - Create a new profile named after the executable itself (e.g. `obs64.exe`).
          Before creating, call `NvAPI_DRS_FindProfileByName` — if a profile with
          that name already exists (e.g. another exe with the same filename or an
          NVPI-created profile), reuse it and set `profile_was_created = false`.
        - Add the application to the profile.
        - Apply exclusion setting `0x809D5F60 = 0x10000000`.
        - Save settings.
     6. Record the rule in the local database.
     7. Return success result with details.

3. **Create `lib/models/add_program_result.dart`**
   ```dart
   class AddProgramResult {
     final bool success;
     final String? errorMessage;
     final String exePath;
     final String exeName;
     final String profileName;
     final bool profileAlreadyExisted;
     final bool exclusionAlreadyApplied;
     final bool needsUserConfirmation;
     final String? confirmationMessage;
   }
   ```

4. **Create the Add Program dialog/flow UI**
   - Create `lib/widgets/add_program_dialog.dart`.
   - Step 1: Show file picker (filter to `.exe` files).
   - Step 2: Show a "checking..." loading state while querying NVAPI.
   - Step 3a: If the exe already has a profile, show a confirmation dialog:
     - "This executable already belongs to profile 'X'."
     - "Would you like to apply the capture exclusion to this existing profile?"
     - [Apply Exclusion] [Cancel]
   - Step 3b: If the exe is new, show a confirmation:
     - "Create a new exclusion rule for {exeName}?"
     - "A new profile named '{exeName}' will be created."
     - [Create Rule] [Cancel]
   - Step 4: Show success or error result.

5. **Wire up the toolbar button**
   - Connect the "Add Program" button in `app_toolbar.dart` to launch the add program flow.

6. **Refresh the managed rules list after adding**
   - After successfully adding a rule, invalidate/refresh the `managedRulesProvider`.
   - Auto-select the newly added rule in the list.

7. **Handle edge cases**
   - User cancels the file picker: do nothing.
   - Selected file is not an .exe: show error.
   - NVAPI is not initialized: show error with instructions.
   - Rule already exists in managed list: show "already managed" message.
   - NVAPI write fails: show error, do not add to local DB.

## Acceptance Criteria

- Clicking "Add Program" opens a Windows file picker filtered to .exe files.
- Selecting an exe correctly checks whether it already has an NVIDIA profile.
- New profiles are created using the executable's filename as the profile name.
- The exclusion setting is applied to the profile.
- The rule is saved to the local database.
- The managed list refreshes and shows the new rule.
- Error cases are handled gracefully with user-friendly messages.
- `flutter analyze` reports no errors.
