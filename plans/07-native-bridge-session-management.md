# 07 - Native Bridge: DRS Session Management

## Goal

Implement DRS (Driver Settings) session lifecycle management in the native bridge.

## Prerequisites

- Plan 06 (Native Bridge Init/Shutdown) completed.

## Background

All NVAPI DRS operations require a session handle. The typical flow is:
1. Create session (`NvAPI_DRS_CreateSession`)
2. Load settings into session (`NvAPI_DRS_LoadSettings`)
3. Perform operations (enumerate, read, write)
4. Save settings if modified (`NvAPI_DRS_SaveSettings`)
5. Destroy session (`NvAPI_DRS_DestroySession`)

The bridge should manage a single session internally so Dart never has to deal with opaque NVAPI handles.

## Tasks

1. **Implement internal session management**
   - Add a global `NvDRSSessionHandle g_session = 0;` in `bridge.cpp`.
   - Session should be created lazily or explicitly.

2. **Implement `bridge_create_session()`**
   ```cpp
   BRIDGE_API int bridge_create_session();
   ```
   - Call `NvAPI_DRS_CreateSession(&g_session)`.
   - Return 0 on success, negative error code on failure.
   - If a session already exists, destroy it first and create a new one.

3. **Implement `bridge_load_settings()`**
   ```cpp
   BRIDGE_API int bridge_load_settings();
   ```
   - Call `NvAPI_DRS_LoadSettings(g_session)`.
   - This loads the current driver profile database into the session.
   - Return 0 on success, negative error code on failure.

4. **Implement `bridge_save_settings()`**
   ```cpp
   BRIDGE_API int bridge_save_settings();
   ```
   - Call `NvAPI_DRS_SaveSettings(g_session)`.
   - This persists any modifications made during the session.
   - Return 0 on success, negative error code on failure.

5. **Implement `bridge_destroy_session()`**
   ```cpp
   BRIDGE_API int bridge_destroy_session();
   ```
   - Call `NvAPI_DRS_DestroySession(g_session)`.
   - Set `g_session = 0`.
   - Safe to call even if no session exists.

6. **Add a convenience function `bridge_open_session()`**
   ```cpp
   BRIDGE_API int bridge_open_session();
   ```
   - Combines create + load in one call.
   - Returns 0 on success, negative on failure.
   - If it fails at load, destroys the partially created session.

7. **Update `native/bridge.h`** with all new declarations.

## Exported Functions After This Plan

```cpp
extern "C" {
    // ... previous functions ...
    BRIDGE_API int bridge_create_session();
    BRIDGE_API int bridge_load_settings();
    BRIDGE_API int bridge_save_settings();
    BRIDGE_API int bridge_destroy_session();
    BRIDGE_API int bridge_open_session();
}
```

## Acceptance Criteria

- Session can be created, loaded, saved, and destroyed without errors.
- `bridge_open_session()` is a reliable single-call entry point.
- Calling destroy on an already-destroyed session does not crash.
- All functions return meaningful error codes.
