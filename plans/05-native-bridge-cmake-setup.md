# 05 - Native Bridge CMake Setup

## Goal

Set up the CMake build configuration and project scaffolding for the native C/C++ bridge DLL (`shadowplay_bridge.dll`) that wraps NVAPI.

## Prerequisites

- Plan 02 (Project Structure) completed.
- NVAPI SDK added as a git submodule from https://github.com/NVIDIA/nvapi at `native/nvapi_sdk/`.

## Background

The design calls for a thin native DLL that sits between Flutter (via `dart:ffi`) and NVAPI. This plan sets up the build system only; actual NVAPI function implementations come in plans 06-11.

The NVAPI SDK is integrated as a GitHub submodule (from `https://github.com/NVIDIA/nvapi`), so developers always have access to the latest updates while maintaining precise version control. After cloning, run `git submodule update --init --recursive` to fetch the SDK.

## Tasks

1. **NVAPI SDK (git submodule)**
   - The SDK is already added as a git submodule at `native/nvapi_sdk/`.
   - After cloning the repo, developers must run: `git submodule update --init --recursive`
   - The submodule provides headers (`nvapi.h`, etc.) and the 64-bit library (`amd64/nvapi64.lib`).

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

7. **Submodule documentation**
   - The SDK files are managed by the git submodule and do not need to be tracked or gitignored separately.
   - README should mention running `git submodule update --init --recursive` after cloning.

## Acceptance Criteria

- `native/` directory exists with `CMakeLists.txt`, `bridge.h`, `bridge.cpp`.
- The bridge compiles as a DLL when the Flutter Windows project is built.
- `shadowplay_bridge.dll` appears in the build output directory.
- Stub functions `bridge_initialize()` and `bridge_shutdown()` are exported and callable.
