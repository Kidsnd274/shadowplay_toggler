# 29 - Error Handling and Notifications

## Goal

Implement a consistent error handling and user notification system across the app.

## Prerequisites

- Plan 14 (App Shell Layout) completed.
- Plan 04 (State Management) completed.

## Tasks

1. **Create a notification service**
   - Create `lib/services/notification_service.dart`.
   - Centralized service for showing user notifications:
     ```dart
     void showSuccess(String message);
     void showError(String message, {String? details});
     void showWarning(String message);
     void showInfo(String message);
     ```
   - Uses Flutter's `ScaffoldMessenger` / `SnackBar` for transient messages.
   - Uses `showDialog` for important confirmations and errors.

2. **Create a notification provider**
   - Create `lib/providers/notification_provider.dart`.
   - Tracks a queue of notifications.
   - Supports different severity levels: success, error, warning, info.

3. **Create styled snackbar widgets**
   - Create `lib/widgets/app_snackbar.dart`.
   - Color-coded by severity:
     - Success: NVIDIA green background
     - Error: red background
     - Warning: amber background
     - Info: blue-grey background
   - Include an icon, message text, and optional "Details" action.
   - Auto-dismiss after a few seconds (configurable).

4. **Create error dialog widget**
   - Create `lib/widgets/error_dialog.dart`.
   - For serious errors that need user attention.
   - Shows:
     - Error icon
     - Error title
     - Error message
     - Optional technical details (expandable)
     - [OK] / [Retry] buttons as appropriate
   - Styled with the app theme.

5. **Create confirmation dialog widget**
   - Create `lib/widgets/confirmation_dialog.dart`.
   - Reusable for all "are you sure?" prompts.
   - Configurable:
     - Title, message
     - Confirm button text and color
     - Cancel button text
     - Optional "don't show again" checkbox

6. **Add global error boundary**
   - Wrap the app in an error handler that catches unhandled Flutter errors.
   - Show a fallback UI instead of crashing.
   - Log errors for debugging.

7. **Standardize error handling in services**
   - Define a custom exception hierarchy:
     ```dart
     class AppException implements Exception {
       final String message;
       final String? technicalDetails;
     }
     class NvapiException extends AppException { ... }
     class DatabaseException extends AppException { ... }
     class FileException extends AppException { ... }
     ```
   - All services should throw typed exceptions.
   - UI layers catch exceptions and show appropriate notifications.

8. **Add the "restart target app" notification**
   - After any driver setting change, show an info snackbar:
     "Restart {exeName} for changes to take effect."
   - This is important because NVIDIA driver settings are applied when the target process initializes the NVIDIA DLL.

## Acceptance Criteria

- All user-facing operations show success/error feedback.
- Error messages are user-friendly, not raw exception dumps.
- Confirmation dialogs appear before destructive actions.
- Snackbars are color-coded and dismissible.
- Global error boundary prevents app crashes.
- Custom exception types are used throughout services.
- `flutter analyze` reports no errors.
