# 05 - Native Bridge CMake Setup

## Goal

Set up the CMake build configuration and project scaffolding for the native C/C++ bridge DLL (`shadowplay_bridge.dll`) that wraps NVAPI.

## Prerequisites

- Plan 02 (Project Structure) completed.
- NVAPI SDK downloaded (https://developer.nvidia.com/rtx/path-tracing/nvapi/get-started). The SDK provides header files and `nvapi64.lib`.

## Background

The design calls for a thin native DLL that sits between Flutter (via `dart:ffi`) and NVAPI. This plan sets up the build system only; actual NVAPI function implementations come in plans 06-11.

## Tasks

1. **Download and place NVAPI SDK**
   - Create directory `native/nvapi_sdk/` at the project root.
   - Place the NVAPI SDK headers and library files there:
     ```
     native/nvapi_sdk/
     ├── nvapi.h
     ├── nvapi_lite_common.h
     ├── nvapi_lite_salstart.h
     ├── nvapi_lite_salend.h
     ├── nvapi_lite_stereo.h
     ├── nvapi_lite_sli.h
     ├── nvapi_lite_surround.h
     ├── NvApiDriverSettings.h
     ├── amd64/
     │   └── nvapi64.lib
     └── ... (other SDK files)
     ```
   - Add a `native/nvapi_sdk/README.md` explaining that these files come from NVIDIA's NVAPI SDK and are not redistributable; developers must download them separately.

2. **Create the bridge source directory**
   ```
   native/
   ├── nvapi_sdk/          (from step 1)
   ├── CMakeLists.txt      (bridge DLL build)
   ├── bridge.h            (public C API header)
   └── bridge.cpp          (implementation - stubs for now)
   ```

3. **Write `native/CMakeLists.txt`**
   - Set `cmake_minimum_required(VERSION 3.14)`.
   - Define project `shadowplay_bridge`.
   - Create a `SHARED` library target: `shadowplay_bridge`.
   - Source files: `bridge.cpp`.
   - Include directories: `nvapi_sdk/`.
   - Link libraries: `nvapi_sdk/amd64/nvapi64.lib`.
   - Set C++ standard to C++17.
   - Use `__declspec(dllexport)` for exported functions (define a macro like `BRIDGE_API`).
   - Set output directory so the DLL lands where the Flutter app can find it.

4. **Write `native/bridge.h`**
   - Define the `BRIDGE_API` export macro:
     ```cpp
     #ifdef BUILDING_BRIDGE
     #define BRIDGE_API __declspec(dllexport)
     #else
     #define BRIDGE_API __declspec(dllimport)
     #endif
     ```
   - Declare stub function signatures (extern "C"):
     ```cpp
     extern "C" {
       BRIDGE_API int bridge_initialize();
       BRIDGE_API void bridge_shutdown();
     }
     ```

5. **Write `native/bridge.cpp`**
   - Include `bridge.h`.
   - Provide stub implementations that return success codes.
   - These will be filled in by plans 06-11.

6. **Integrate with the Flutter Windows build**
   - Modify `windows/CMakeLists.txt` to add the native bridge as a subdirectory or external project.
   - Ensure `shadowplay_bridge.dll` is copied to the Flutter app's build output directory alongside the executable.
   - The DLL must be in the same directory as `shadowplay_toggler.exe` at runtime.

7. **Add `native/` to `.gitignore` exceptions**
   - Make sure `native/nvapi_sdk/*.lib` and `native/nvapi_sdk/*.h` are either tracked or documented as manual downloads.
   - Consider gitignoring the SDK files and adding a setup script or instructions.

## Acceptance Criteria

- `native/` directory exists with `CMakeLists.txt`, `bridge.h`, `bridge.cpp`.
- The bridge compiles as a DLL when the Flutter Windows project is built.
- `shadowplay_bridge.dll` appears in the build output directory.
- Stub functions `bridge_initialize()` and `bridge_shutdown()` are exported and callable.
