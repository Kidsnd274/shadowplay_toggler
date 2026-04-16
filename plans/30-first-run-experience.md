# 30 - First Run Experience

## Goal

Create a polished first-run experience that guides new users through the app's purpose and initial setup.

## Prerequisites

- Plan 14 (App Shell Layout) completed.
- Plan 23 (Scan Profiles Feature) completed.
- Plan 24 (Backup/Restore Feature) completed.
- Plan 29 (Error Handling) completed.

## Background

On first launch, the Managed list is empty. The user needs to understand what the app does, optionally scan for existing rules, and ideally create a backup before making changes.

## Tasks

1. **Detect first run**
   - Check the app state database for a `first_run_completed` flag.
   - If false or missing, trigger the first-run flow.

2. **Create a welcome screen/overlay**
   - Create `lib/widgets/welcome_overlay.dart`.
   - Shown as a modal overlay or a full-screen page on first launch.
   - Content:
     - App logo/name: "ShadowPlay Toggler"
     - Brief explanation (2-3 sentences):
       "This app helps you manage which programs are excluded from NVIDIA's overlay and capture features (ShadowPlay, Instant Replay). Add programs to prevent NVIDIA from recording or overlaying on them."
     - Steps the user can take:
       1. "Scan for existing rules" - checks what's already configured in the driver
       2. "Create a backup" - saves current driver settings before making changes
       3. "Add your first program" - start managing exclusions
     - [Get Started] button to dismiss

3. **Offer initial scan**
   - After the welcome screen, prompt: "Would you like to scan your NVIDIA driver profiles to see what's already configured?"
   - [Scan Now] [Skip]
   - If the user scans, populate the Detected and Defaults tabs.

4. **Offer initial backup**
   - After scan (or skip), prompt: "We recommend creating a backup of your driver settings before making any changes."
   - [Create Backup] [Skip]
   - If created, set `first_backup_done = true`.

5. **Enhance empty states**
   - The Managed tab empty state should be friendly and actionable:
     - Large icon (e.g., a shield or list icon)
     - "No exclusion rules yet"
     - "Click 'Add Program' in the toolbar to exclude an app from NVIDIA overlay capture."
     - Optional: show a subtle arrow/highlight pointing to the Add Program button.

6. **Set first-run flag**
   - After the welcome flow completes (user clicks "Get Started"), set `first_run_completed = true` in the app state database.
   - The welcome overlay should not appear again.

7. **Add "What's New" for future versions (optional)**
   - Store the last shown version in app state.
   - If the app version is newer, show a "What's New" dialog.
   - Not needed for v1, but the infrastructure should be in place.

8. **Handle NVAPI unavailable on first run**
   - If NVAPI fails to initialize on first run:
     - Show a clear error in the welcome flow.
     - "NVIDIA GPU or drivers not detected. This app requires an NVIDIA GPU with drivers installed."
     - [Exit] [Continue Anyway (limited mode)]

## Acceptance Criteria

- First launch shows a welcome overlay with clear explanation.
- User is prompted to scan and create a backup.
- Empty states are friendly and guide the user to take action.
- First-run flag is persisted so the overlay only shows once.
- NVAPI unavailability is handled gracefully.
- `flutter analyze` reports no errors.
