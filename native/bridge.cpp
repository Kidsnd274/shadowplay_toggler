#include <windows.h>
#include <cstdio>
#include <cstring>
#include "bridge.h"
#include "nvapi.h"

static bool g_initialized = false;
static char g_error_buffer[256] = {0};

int bridge_initialize() {
    if (g_initialized) {
        return 0;
    }

    NvAPI_Status status = NvAPI_Initialize();
    if (status == NVAPI_OK) {
        g_initialized = true;
        return 0;
    }

    if (status == NVAPI_NVIDIA_DEVICE_NOT_FOUND ||
        status == NVAPI_NO_IMPLEMENTATION) {
        return -1;
    }

    return -2;
}

void bridge_shutdown() {
    if (g_initialized) {
        NvAPI_Unload();
        g_initialized = false;
    }
}

int bridge_is_initialized() {
    return g_initialized ? 1 : 0;
}

const char* bridge_get_error_message(int nvapi_status) {
    NvAPI_ShortString desc = {0};
    NvAPI_Status result = NvAPI_GetErrorMessage(
        static_cast<NvAPI_Status>(nvapi_status), desc);

    if (result == NVAPI_OK) {
        strncpy_s(g_error_buffer, sizeof(g_error_buffer), desc, _TRUNCATE);
    } else {
        _snprintf_s(g_error_buffer, sizeof(g_error_buffer), _TRUNCATE,
                     "Unknown NVAPI error (code %d)", nvapi_status);
    }

    return g_error_buffer;
}
