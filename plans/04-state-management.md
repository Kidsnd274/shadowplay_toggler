# 04 - State Management

## Goal

Set up Riverpod as the state management solution and create the core provider structure.

## Prerequisites

- Plan 02 (Project Structure) completed.

## Tasks

1. **Add dependencies to `pubspec.yaml`**
  - Add `flutter_riverpod` (latest stable) to dependencies.
2. **Wrap the app in `ProviderScope`**
  - In `lib/main.dart`, wrap the root widget with `ProviderScope`.
3. **Create core provider files in `lib/providers/`**
  - `lib/providers/nvapi_provider.dart` - Placeholder provider for NVAPI bridge service state (initialized, error, etc.). Use a simple `StateNotifierProvider` or `AsyncNotifierProvider` that starts in an "uninitialized" state.
  - `lib/providers/managed_rules_provider.dart` - Placeholder provider for the managed rules list. Initially returns an empty list.
  - `lib/providers/detected_rules_provider.dart` - Placeholder provider for detected existing rules. Initially returns an empty list.
  - `lib/providers/selected_rule_provider.dart` - Provider for the currently selected rule in the UI. Initially null.
4. **Define placeholder state classes in `lib/models/`**
  - `lib/models/nvapi_state.dart` - Enum or sealed class for NVAPI states: `uninitialized`, `initializing`, `ready`, `error(String message)`.
  - `lib/models/exclusion_rule.dart` - Data class for an exclusion rule:
    ```dart
    class ExclusionRule {
      final String exePath;
      final String exeName;
      final String profileName;
      final bool isManaged;
      final bool isPredefined;
      final int currentValue;
      final int? previousValue;
      final String sourceType; // 'managed', 'external', 'nvidia_default', 'inherited'
      final DateTime? createdAt;
      final DateTime? updatedAt;
    }
    ```
5. **Update `home_screen.dart` to be a `ConsumerWidget`**
  - Convert `HomeScreen` from `StatelessWidget` to `ConsumerWidget`.
  - Watch the NVAPI provider and display its state (e.g., "NVAPI: Uninitialized").

## Acceptance Criteria

- `flutter_riverpod` is in `pubspec.yaml` and `pubspec.lock`.
- `ProviderScope` wraps the app.
- All four providers exist and are importable.
- `ExclusionRule` and `NvapiState` models are defined.
- `HomeScreen` is a `ConsumerWidget` that reads from a provider.
- `flutter analyze` reports no errors.
- `flutter test` passes.

