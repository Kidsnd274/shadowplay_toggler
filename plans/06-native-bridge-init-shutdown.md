# 06 - Native Bridge: Initialize and Shutdown

## Goal

Implement the NVAPI initialization and shutdown logic in the native bridge.

## Prerequisites

- Plan 05 (Native Bridge CMake Setup) completed.
- NVAPI SDK headers and library available in `native/nvapi_sdk/`.

## Background

NVAPI requires calling `NvAPI_Initialize()` before any other API calls, and `NvAPI_Unload()` for cleanup. The bridge should manage this lifecycle and report status back to Dart.

## Tasks

1. **Implement `bridge_initialize()` in `native/bridge.cpp`**
   - Call `NvAPI_Initialize()`.
   - Check the return status (`NVAPI_OK` = success).
   - Return an integer status code:
     - `0` = success
     - `-1` = NVAPI not available (no NVIDIA GPU or driver)
     - `-2` = initialization failed (return the NVAPI error code somehow)
   - Store a global boolean `g_initialized` to track state.
   - If already initialized, return success immediately (idempotent).

2. **Implement `bridge_shutdown()` in `native/bridge.cpp`**
   - Call `NvAPI_Unload()`.
   - Set `g_initialized = false`.
   - Should be safe to call multiple times.

3. **Add `bridge_get_error_message()` function**
   - Declare and implement:
     ```cpp
     BRIDGE_API const char* bridge_get_error_message(int nvapi_status);
     ```
   - Use `NvAPI_GetErrorMessage()` to convert an NVAPI status code to a human-readable string.
   - Return a pointer to a static buffer (safe for FFI).

4. **Add `bridge_is_initialized()` function**
   - Declare and implement:
     ```cpp
     BRIDGE_API int bridge_is_initialized();
     ```
   - Returns 1 if initialized, 0 if not.

5. **Update `native/bridge.h`**
   - Add all new function declarations.

## Exported Functions After This Plan

```cpp
extern "C" {
    BRIDGE_API int bridge_initialize();
    BRIDGE_API void bridge_shutdown();
    BRIDGE_API int bridge_is_initialized();
    BRIDGE_API const char* bridge_get_error_message(int nvapi_status);
}
```

## Acceptance Criteria

- `bridge_initialize()` successfully calls `NvAPI_Initialize()` and returns 0 on a machine with NVIDIA GPU.
- `bridge_shutdown()` cleans up without errors.
- `bridge_is_initialized()` returns correct state.
- `bridge_get_error_message()` returns readable error strings.
- Functions are idempotent and safe to call multiple times.
