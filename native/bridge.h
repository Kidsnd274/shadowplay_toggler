#pragma once

#ifdef BUILDING_BRIDGE
#define BRIDGE_API __declspec(dllexport)
#else
#define BRIDGE_API __declspec(dllimport)
#endif

extern "C" {
    // Returns 0 on success, -1 if NVAPI is unavailable, -2 on init failure.
    BRIDGE_API int bridge_initialize();

    BRIDGE_API void bridge_shutdown();

    // Returns 1 if initialized, 0 if not.
    BRIDGE_API int bridge_is_initialized();

    // Converts an NvAPI status code to a human-readable string.
    // Returns a pointer to a static buffer (safe for FFI).
    BRIDGE_API const char* bridge_get_error_message(int nvapi_status);
}
