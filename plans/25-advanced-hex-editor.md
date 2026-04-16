# 25 - Advanced Hex Editor

## Goal

Implement the advanced mode panel that lets power users directly view and edit the raw hex value of setting `0x809D5F60`.

## Prerequisites

- Plan 20 (Rule Detail View) completed.
- Plan 12 (Dart FFI Bindings) completed (for reading/writing settings).

## Background

From `design.md`: Advanced mode should expose the raw setting ID, hex value editor, current/predefined source info, and reset to default. Because undocumented settings may not have a public semantic map, advanced mode should present raw hex values honestly and warn that behavior may vary by driver version.

## Tasks

1. **Create `lib/widgets/advanced_editor.dart`**
   - A panel/dialog that appears when the user clicks "Advanced" in the rule detail view.
   - Can be an expandable section within the detail view or a modal dialog.
   - Expandable section is preferred (keeps context visible).

2. **Display raw setting information**
   - Setting ID: `0x809D5F60` (read-only, monospace)
   - Setting Name: from NVAPI if available, or "Unknown / Community-identified" 
   - Current Value: hex display (e.g., `0x10000000`)
   - Predefined Value: hex display if different
   - Is Current Predefined: Yes/No
   - Setting Location: where the current value comes from

3. **Build the hex value editor**
   - A `TextField` for entering a raw hex value.
   - Input validation: must be a valid hex number (with or without `0x` prefix).
   - Show the decimal equivalent next to the hex value.
   - "Apply" button to write the new value.
   - "Reset to Default" button.

4. **Add known value reference**
   - Show a small table or dropdown of known values:
     ```
     0x10000000 = Exclude from capture (community-identified)
     (default)  = No exclusion override
     ```
   - Selecting a known value fills the editor field.
   - This list can be expanded if more values are discovered.

5. **Add warnings**
   - Show a persistent warning banner:
     "Advanced mode: This setting is not officially documented by NVIDIA. Values may behave differently across driver versions. Use at your own risk."
   - Yellow/amber warning style.

6. **Wire up to NVAPI service**
   - "Apply" calls `nvapiService.setDwordSetting(profileIndex, settingId, value)` then `nvapiService.saveSettings()`.
   - "Reset to Default" calls `nvapiService.restoreSettingDefault(profileIndex, settingId)`.
   - Show success/error feedback after each operation.
   - Refresh the rule detail view after changes.

7. **Track changes in local DB**
   - After applying a custom value, update the managed rule's `intendedValue` in the local database.

## Acceptance Criteria

- Advanced panel shows all raw setting information.
- Hex editor accepts valid hex input and validates it.
- Known values are listed as a quick reference.
- Warning banner is always visible in advanced mode.
- Apply and Reset buttons work and provide feedback.
- The rule detail view refreshes after changes.
- `flutter analyze` reports no errors.
