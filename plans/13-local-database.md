# 13 - Local Database

## Goal

Set up local persistence for managed rules and app state using a lightweight database.

## Prerequisites

- Plan 04 (State Management) completed (model classes defined).
- Plan 02 (Project Structure) completed.

## Background

The design calls for a hybrid model: NVIDIA's DRS database is the source of truth for current driver state, while the local app database stores user intent, managed rule metadata, and rollback information. This local DB must survive app restarts and support the reconciliation process on startup.

## Tasks

1. **Choose and add database dependency**
   - Use `sqflite_common_ffi` for Windows desktop SQLite support.
   - Add to `pubspec.yaml`:
     - `sqflite_common_ffi` (latest)
     - `path_provider` (latest, for getting app data directory)
     - `path` (for path manipulation)

2. **Create `lib/services/database_service.dart`**
   - Initialize SQLite using `sqflite_common_ffi` (required for Windows desktop; standard `sqflite` doesn't support desktop).
   - Database file location: `%APPDATA%/ShadowPlayToggler/managed_rules.db`
   - Create tables on first run.

3. **Define the database schema**

   **Table: `managed_rules`**
   ```sql
   CREATE TABLE managed_rules (
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     exe_path TEXT NOT NULL UNIQUE,
     exe_name TEXT NOT NULL,
     profile_name TEXT NOT NULL,
     profile_was_predefined INTEGER NOT NULL DEFAULT 0,
     profile_was_created INTEGER NOT NULL DEFAULT 0,
     intended_value INTEGER NOT NULL DEFAULT 0x10000000,
     previous_value INTEGER,
     driver_version TEXT,
     created_at TEXT NOT NULL,
     updated_at TEXT NOT NULL
   );
   ```

   **Table: `app_state`**
   ```sql
   CREATE TABLE app_state (
     key TEXT PRIMARY KEY,
     value TEXT NOT NULL
   );
   ```
   Used for storing things like:
   - `first_backup_done` = "true"/"false"
   - `last_scan_timestamp` = ISO 8601
   - `last_driver_version` = string
   - `drs_profile_hash` = hash of profile names/counts from the last successful reconciliation (see note below)

   > **Driver-install resilience:** The SQLite database persists across NVIDIA driver
   > reinstalls, but the NVIDIA DRS database resets to factory defaults on each install.
   > This means every managed rule in our DB could become orphaned overnight. The
   > `last_driver_version` key lets plan 26's reconciliation detect a version change
   > and trigger a bulk re-apply flow instead of treating each rule as individually
   > orphaned. The `drs_profile_hash` provides a secondary signal: even if the driver
   > version string doesn't change (e.g. same-version repair install), a hash mismatch
   > indicates the DRS was likely reset.

4. **Create `lib/services/managed_rules_repository.dart`**
   - CRUD operations for managed rules:
     ```dart
     Future<List<ManagedRule>> getAllRules();
     Future<ManagedRule?> getRuleByExePath(String exePath);
     Future<int> insertRule(ManagedRule rule);
     Future<void> updateRule(ManagedRule rule);
     Future<void> deleteRule(int id);
     Future<void> deleteRuleByExePath(String exePath);
     Future<List<ManagedRule>> getRulesMatchingPrefix(String prefix);
     ```

5. **Create `lib/models/managed_rule.dart`**
   - Data class that maps to the `managed_rules` table:
     ```dart
     class ManagedRule {
       final int? id;
       final String exePath;
       final String exeName;
       final String profileName;
       final bool profileWasPredefined;
       final bool profileWasCreated;
       final int intendedValue;
       final int? previousValue;
       final String? driverVersion;
       final DateTime createdAt;
       final DateTime updatedAt;

       Map<String, dynamic> toMap();
       factory ManagedRule.fromMap(Map<String, dynamic> map);
     }
     ```

6. **Create `lib/services/app_state_repository.dart`**
   - Key-value operations for app state:
     ```dart
     Future<String?> getValue(String key);
     Future<void> setValue(String key, String value);
     Future<bool> getBool(String key);
     Future<void> setBool(String key, bool value);
     ```

7. **Wire up to Riverpod**
   - Create a provider for the database service in `lib/providers/`.
   - The database should be initialized once at app startup.
   - The managed rules provider (from plan 04) should read from this repository.

8. **Write tests**
   - Test CRUD operations using an in-memory SQLite database.
   - Test `ManagedRule` serialization/deserialization.

## Acceptance Criteria

- SQLite database is created on first run in the app data directory.
- Managed rules can be created, read, updated, and deleted.
- App state key-value pairs persist across restarts.
- Database provider is available via Riverpod.
- `flutter analyze` reports no errors.
- Tests pass with in-memory database.
