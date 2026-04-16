# 03 - App Theme

## Goal

Implement the dark NVIDIA-inspired visual theme described in the design document.

## Prerequisites

- Plan 02 (Project Structure) completed.

## Design Spec

From `design.md`:

- Background: dark charcoal
- Panels: slightly lighter graphite
- Accent: NVIDIA green
- Buttons: rectangular, 4-6px radius max
- Borders: visible, sharp
- Typography: compact, high contrast
- Icons: simple line icons, minimal decoration
- Style: "tool-like, not gamer flashy"

## Tasks

1. **Create `lib/constants/app_theme.dart`**
  - Define the full `ThemeData` for the app.
  - Color palette:
    - `scaffoldBackgroundColor`: dark charcoal (e.g., `Color(0xFF1A1A1A)`)
    - Card/panel surfaces: slightly lighter graphite (e.g., `Color(0xFF2A2A2A)`)
    - Primary/accent: NVIDIA green (e.g., `Color(0xFF76B900)`)
    - Text: high contrast white/light grey on dark
    - Error: standard red
    - Borders: visible grey (e.g., `Color(0xFF3A3A3A)`)
  - Button themes:
    - `ElevatedButtonThemeData` with rectangular shape, 4-6px border radius, NVIDIA green background.
    - `OutlinedButtonThemeData` with visible border, same radius.
    - `TextButtonThemeData` with NVIDIA green text.
  - `CardTheme` with graphite color, sharp corners (4px radius), visible border.
  - `AppBarTheme` with dark charcoal background, no elevation, compact.
  - `InputDecorationTheme` for text fields: outlined border style, grey border, green focus color.
  - `TabBarTheme` with NVIDIA green indicator and white labels.
  - `DividerTheme` with visible grey color.
  - Typography: use default Material font but set compact `bodyMedium`, `titleMedium`, etc. with light colors.
2. **Apply the theme in `lib/app.dart`**
  - Set `theme:` to the new `AppTheme.darkTheme`.
  - Set `darkTheme:` to the same theme.
  - Set `themeMode: ThemeMode.dark`.
3. **Verify visual appearance**
  - The placeholder home screen should render with the dark charcoal background and NVIDIA green accents.

## Acceptance Criteria

- `app_theme.dart` exports a complete `ThemeData`.
- The app renders with the dark charcoal + NVIDIA green color scheme.
- Buttons, cards, tabs, and input fields all follow the theme spec.
- `flutter analyze` reports no errors.