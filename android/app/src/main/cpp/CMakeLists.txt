cmake_minimum_required(VERSION 3.22.1)
project(wcpp_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Keep whisper inference usable during `flutter run --debug`.
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O3 -DNDEBUG")

set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/whispercpp
  ${CMAKE_CURRENT_BINARY_DIR}/whispercpp
)

add_library(wcpp_bridge SHARED wcpp_bridge.cpp)

target_include_directories(wcpp_bridge PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/whispercpp/include
)

target_link_libraries(wcpp_bridge PRIVATE
  whisper
  log
  android
)
