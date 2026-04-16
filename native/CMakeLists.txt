cmake_minimum_required(VERSION 3.14)
project(shadowplay_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(shadowplay_bridge SHARED
  bridge.cpp
)

target_compile_definitions(shadowplay_bridge PRIVATE
  BUILDING_BRIDGE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
)

target_compile_options(shadowplay_bridge PRIVATE /W3 /EHsc)

target_include_directories(shadowplay_bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/nvapi_sdk"
)

target_link_libraries(shadowplay_bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/nvapi_sdk/amd64/nvapi64.lib"
)
