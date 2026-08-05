cmake_minimum_required(VERSION 3.13)
project(qunleashed_hardnested LANGUAGES C)

# Host-side hardnested attack. Engine + embedded XZ bitflip tables + minlzlib are
# vendored from ChameleonUltraGUI (GPL, Proxmark3-derived). Single SIMD variant
# (baseline SSE2/NEON on GCC/Clang, scalar on MSVC) so it builds with the default
# toolchain on every platform - no clang-cl required. See BUILD_NOTES.md.

add_library(qunleashed_hardnested SHARED
  qunleashed_hardnested_bridge.c
  hardnested.c
  crapto1.c
  crypto1.c
  bucketsort.c
  parity.c
  hardnested/hardnested_bf_core.c
  hardnested/hardnested_bitarray_core.c
  hardnested/hardnested_bruteforce.c
  hardnested/tables.c
  pm3/commonutil.c
  pm3/ui.c
  pm3/util.c
  pm3/util_posix.c
  minlzlib/inputbuf.c
  minlzlib/dictbuf.c
  minlzlib/lzma2dec.c
  minlzlib/lzmadec.c
  minlzlib/rangedec.c
  minlzlib/xzcrc.c
  minlzlib/xzstream.c
)

target_include_directories(qunleashed_hardnested PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/hardnested"
  "${CMAKE_CURRENT_SOURCE_DIR}/minlzlib"
  "${CMAKE_CURRENT_SOURCE_DIR}/pm3"
)

set_target_properties(qunleashed_hardnested PROPERTIES
  C_STANDARD 11
  POSITION_INDEPENDENT_CODE ON
)

# Perf: -O3 on GCC/Clang. MSVC uses its own default optimization.
if(NOT MSVC)
  target_compile_options(qunleashed_hardnested PRIVATE -O3)
endif()

# MinGW defines _WIN32 but ships no MSVC sal.h (used by minlzlib). Real MSVC has
# it; Linux/macOS/Android never take the _WIN32 path.
if(MINGW)
  target_compile_definitions(qunleashed_hardnested PRIVATE "_In_=")
endif()

# Threads: real pthreads on Linux/Android/macOS/iOS and MinGW (winpthreads);
# clang-cl/MSVC use the bundled pthread_shim.h (Win32 APIs, no extra library).
if(NOT (WIN32 AND NOT MINGW))
  find_package(Threads REQUIRED)
  target_link_libraries(qunleashed_hardnested PRIVATE Threads::Threads)
endif()

if(WIN32)
  target_compile_definitions(qunleashed_hardnested PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
