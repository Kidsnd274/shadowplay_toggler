# 27 - Adopt Existing Rules (Post-MVP)

## Goal

Allow users to "adopt" detected external exclusion rules into their managed list, giving the app control over rules it did not create.

## Prerequisites

- Plan 17 (Detected Rules List) completed.
- Plan 13 (Local Database) completed.
- Plan 20 (Rule Detail View) completed.

## Background

From `design.md`: If the app finds `0x809D5F60` overrides that are not in its DB, show them as unmanaged and let the user adopt them. This is a post-MVP feature.

## Tasks

1. **Create `lib/services/adopt_rule_service.dart`**
   - Method:
     ```dart
     Future<AdoptResult> adoptRule(ExclusionRule detectedRule);
     ```
   - Logic:
     1. Read the current setting value and profile info from the driver.
     2. Create a `ManagedRule` entry in the local database with:
        - `profileWasPredefined = true` (or based on actual status)
        - `profileWasCreated = false` (we didn't create it)
        - `previousValue` = current value before our management
        - `intendedValue` = current value (we're adopting it as-is)
     3. Move the rule from the detected list to the managed list in UI state.

2. **Add "Adopt" button to the detail view**
   - When a detected (external) rule is selected in the detail view:
     - Show an "Adopt this rule" button instead of the normal toggle.
     - Explanation text: "Take control of this rule. It will appear in your Managed list."
   - When clicked:
     - Show confirmation: "Adopt exclusion rule for {exeName}? This rule was created externally. Adopting it lets you manage it from this app."
     - [Adopt] [Cancel]

3. **Add "Adopt All" batch action (optional)**
   - In the Detected tab header, show an "Adopt All" button if there are detected rules.
   - Adopts all detected rules at once.
   - Show summary after: "Adopted X rules."

4. **Refresh lists after adoption**
   - Remove the adopted rule from `detectedRulesProvider`.
   - Add it to `managedRulesProvider`.
   - Auto-select it in the managed list.

5. **Handle edge cases**
   - Rule was already adopted: show "already managed" message.
   - Profile was deleted since scan: show error.
   - Setting value changed since scan: warn the user and re-read.

## Acceptance Criteria

- Users can adopt individual detected rules.
- Adopted rules move from Detected to Managed tab.
- The local database records the adoption with correct metadata.
- The rule detail view shows appropriate controls for detected vs managed rules.
- `flutter analyze` reports no errors.
