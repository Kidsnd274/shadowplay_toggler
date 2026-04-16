# 27 - Adopt Existing Rules

## Goal

Allow users to "adopt" detected external exclusion rules into their managed list, giving the app control over rules it did not create.

This feature is part of the **MVP**, not post-MVP. Because the app no longer tags its own profiles with a prefix, manual adoption is the only way to reconstruct the managed list after a local-DB loss. It also remains the right pattern for rules created by other tools (NVPI, games, NVIDIA GeForce Experience).

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
     1. Read the current setting value and profile info from the driver (so the adoption captures live state, not stale scan data).
     2. Create a `ManagedRule` entry in the local database with:
        - `profileWasPredefined` = live `isPredefined` flag from the DRS setting.
        - `profileWasCreated = false` (we didn't create it; even if we had, we can't prove it without the prefix and should not claim authorship on adoption).
        - `previousValue` = current value at adoption time. Note this is the best we can do — the user's pre-app-ever-touching-it value is no longer knowable, but capturing the adoption-time value means "Restore Default" behaviour is still deterministic at the driver level via `RestoreProfileDefaultSetting` / `DeleteSetting`.
        - `intendedValue` = current value (we're adopting it as-is; if the user later wants to change it, they can toggle).
     3. Move the rule from the detected list to the managed list in UI state.

2. **Add "Adopt" button to the detail view**
   - When a detected (external) rule is selected in the detail view:
     - Show an "Adopt this rule" button instead of the normal toggle.
     - Explanation text: "Take control of this rule. It will appear in your Managed list."
   - When clicked:
     - Show confirmation: "Adopt exclusion rule for {exeName}? This rule was created externally. Adopting it lets you manage it from this app."
     - [Adopt] [Cancel]

3. **Add "Adopt All" batch action**
   - In the Detected tab header, show an "Adopt All" button if there are detected rules.
   - Adopts all detected rules at once.
   - Show summary after: "Adopted X rules."
   - This is the recovery path after a local-DB loss — the user can rebuild their managed list in a single click.

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
