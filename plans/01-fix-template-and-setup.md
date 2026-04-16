# 01 - Fix Template and Setup

## Goal

Fix the broken default Flutter counter template and prepare a clean slate for the ShadowPlay Toggler app.

## Prerequisites

- None (this is the first task)

## Current State

`lib/main.dart` has two bugs inherited from a bad template generation:

- `colorScheme: .fromSeed(...)` should be `colorScheme: ColorScheme.fromSeed(...)`
- `mainAxisAlignment: .center` should be `mainAxisAlignment: MainAxisAlignment.center`

`test/widget_test.dart` imports `main.dart` and tests the counter, so it will also fail.

## Tasks

1. **Fix `lib/main.dart`**
  - Replace the counter demo with a minimal placeholder app.
  - The app should show a centered `Text` widget saying "ShadowPlay Toggler" on a dark background.
  - Use `MaterialApp` with a basic dark theme (will be fully themed later in plan 03).
  - Remove all counter-related code (`_incrementCounter`, `_counter`, `FloatingActionButton`, etc.).
2. **Fix `test/widget_test.dart`**
  - Replace the counter widget test with a simple smoke test that verifies the app renders without crashing.
  - Test should pump `MyApp` (or whatever the root widget is named) and verify it finds the title text.
3. **Update `pubspec.yaml`**
  - Verify `name: shadowplay_toggler` is correct.
  - Update `description` to: "ShadowPlay Toggler - manage per-app ShadowPlay/Overlay exclusions."
  - Keep `version: 1.0.0+1`.
  - Remove `cupertino_icons` from dependencies (not needed for a Windows-only app).
4. **Update `README.md`**
  - Replace the generic Flutter readme with a brief project description:
    - Project name: ShadowPlay Toggler
    - Purpose: Manage per-application NVIDIA capture/overlay exclusions via DRS profiles
    - Platform: Windows only
    - Tech: Flutter desktop + native C/C++ NVAPI bridge
    - Status: In development
5. **Verify the app compiles**
  - Run `flutter analyze` and confirm no errors.
  - Run `flutter test` and confirm the smoke test passes.

## Acceptance Criteria

- `flutter analyze` reports no errors.
- `flutter test` passes.
- The app launches with `flutter run -d windows` and shows the placeholder screen.
- No counter demo code remains.
- `cupertino_icons` is removed from `pubspec.yaml`.