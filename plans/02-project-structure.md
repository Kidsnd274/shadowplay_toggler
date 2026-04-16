# 02 - Project Structure

## Goal

Establish the folder structure and placeholder files for the Flutter app so subsequent features have clear places to put code.

## Prerequisites

- Plan 01 (Fix Template and Setup) completed.

## Tasks

1. **Create the following directory structure under `lib/`:**

```
lib/
├── main.dart                  (already exists)
├── app.dart                   (MaterialApp widget, extracted from main.dart)
├── models/
│   └── .gitkeep
├── services/
│   └── .gitkeep
├── providers/
│   └── .gitkeep
├── screens/
│   └── home_screen.dart       (placeholder home screen)
├── widgets/
│   └── .gitkeep
└── constants/
    └── app_constants.dart     (setting IDs, profile prefix, etc.)
```

1. **Extract `MaterialApp` into `app.dart`**
  - Create `lib/app.dart` containing a `CaptureExclusionApp` widget (or `ShadowPlayTogglerApp`) that returns the `MaterialApp`.
  - `main.dart` should only contain `void main() => runApp(CaptureExclusionApp());`
2. **Create `lib/screens/home_screen.dart`**
  - Move the placeholder UI (centered title text) into `HomeScreen` widget.
  - `MaterialApp` in `app.dart` should use `HomeScreen` as its `home:`.
3. **Create `lib/constants/app_constants.dart`**
  - Define constants that will be used throughout the app:
4. **Update `test/widget_test.dart`**
  - Update imports to reference `app.dart` instead of `main.dart`.

## Acceptance Criteria

- All directories exist with `.gitkeep` files where empty.
- `main.dart` is minimal (just `runApp`).
- `app.dart` contains the `MaterialApp` widget.
- `home_screen.dart` renders the placeholder UI.
- `app_constants.dart` defines the core constants.
- `flutter analyze` reports no errors.
- `flutter test` passes.

