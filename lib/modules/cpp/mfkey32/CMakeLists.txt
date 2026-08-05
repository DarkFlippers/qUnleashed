cmake_minimum_required(VERSION 3.13)
project(qunleashed_mfkey32 LANGUAGES C)

set(NFC_TOOLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../nfc-tools")
set(CRAPTO1_DIR "${NFC_TOOLS_DIR}/mfkey32v2/crapto1")
set(HARDNESTED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../hardnested")
set(LZ4_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../lz4")

# Include dirs the hardnested sources need:
#  - HARDNESTED_DIR       : hn_compat.h, engine headers, bzlib_stub.h
#  - LZ4_DIR              : vendored lz4frame.h etc.
#  - mfkey32v2            : resolves "crapto1/crapto1.h"
#  - CRAPTO1_DIR          : resolves "parity.h"
set(HN_INCLUDE_DIRS
  "${HARDNESTED_DIR}"
  "${LZ4_DIR}"
  "${NFC_TOOLS_DIR}/mfkey32v2"
  "${CRAPTO1_DIR}")

# --- Toolchain detection: real MSVC vs clang-cl (Clang with the MSVC driver) ---
# The hardnested engine relies on GCC/Clang vector extensions, __builtin_* and
# VLAs. Real MSVC (cl.exe) cannot compile it, so the Windows desktop build must
# use clang-cl; real-MSVC configs still build the other attacks (hardnested is
# skipped). msvc_compat.h (which #defines __attribute__ away under _MSC_VER)
# must NOT be force-included under clang-cl or it would collapse the SIMD vector
# types - so it is applied to real MSVC only.
set(IS_REAL_MSVC FALSE)
set(IS_CLANG_CL FALSE)
if(CMAKE_C_COMPILER_ID STREQUAL "MSVC")
  set(IS_REAL_MSVC TRUE)
elseif(MSVC AND CMAKE_C_COMPILER_ID MATCHES "Clang")
  set(IS_CLANG_CL TRUE)
endif()

set(HN_SUPPORTED TRUE)
if(IS_REAL_MSVC)
  set(HN_SUPPORTED FALSE)
  message(WARNING "qunleashed: hardnested disabled under real MSVC; "
                  "configure the Windows build with the clang-cl toolset to enable it.")
endif()

# Prefix to pass clang -m/-f flags through the clang-cl (MSVC-style) driver.
if(IS_CLANG_CL)
  set(MP "/clang:")
else()
  set(MP "")
endif()

set(HN_SIMD_OBJECTS "")

if(HN_SUPPORTED)
  # -------------------------------------------------------------------------
  # Hardnested SIMD engine: hardnested_bf_core.c + hardnested_bitarray_core.c
  # are compiled once per instruction set, each emitting suffixed symbols
  # (_NOSIMD/_MMX/_SSE2/_AVX/_AVX2/_AVX512 on x86, _NEON on ARM). The runtime
  # dispatcher lives in the NOSIMD object and picks the best variant, so every
  # variant for the target arch must be linked. Mirrors proxmark3
  # client/deps/hardnested.cmake.
  # -------------------------------------------------------------------------
  set(HN_SIMD_SRCS
    "${HARDNESTED_DIR}/hardnested_bf_core.c"
    "${HARDNESTED_DIR}/hardnested_bitarray_core.c")

  # Each variant is an OBJECT library. ARGN = extra per-variant compile flags.
  # -fcommon is required: the engine relies on tentative (common) globals that
  # would otherwise clash across the identically-named per-ISA objects.
  function(hn_add_variant name)
    add_library(${name} OBJECT ${HN_SIMD_SRCS})
    set_property(TARGET ${name} PROPERTY POSITION_INDEPENDENT_CODE ON)
    target_include_directories(${name} PRIVATE ${HN_INCLUDE_DIRS})
    target_compile_options(${name} PRIVATE ${MP}-O3 ${MP}-fcommon ${ARGN})
    set(HN_SIMD_OBJECTS ${HN_SIMD_OBJECTS} $<TARGET_OBJECTS:${name}> PARENT_SCOPE)
  endfunction()

  set(X86_CPUS x86 x86_64 i686 AMD64)
  set(ARM64_CPUS arm64 aarch64 arm64-v8a)
  set(ARM32_CPUS armel armhf armv7-a armeabi-v7a)

  message(STATUS "qunleashed hardnested: CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}")

  # nosimd variant is always built and also carries the dispatcher.
  hn_add_variant(qunleashed_hn_nosimd -DNOSIMD_BUILD)

  if(CMAKE_SYSTEM_PROCESSOR IN_LIST X86_CPUS)
    target_compile_options(qunleashed_hn_nosimd BEFORE PRIVATE
      ${MP}-mno-mmx ${MP}-mno-sse2 ${MP}-mno-avx ${MP}-mno-avx2 ${MP}-mno-avx512f)
    hn_add_variant(qunleashed_hn_mmx    ${MP}-mmmx  ${MP}-mno-sse2 ${MP}-mno-avx  ${MP}-mno-avx2  ${MP}-mno-avx512f)
    hn_add_variant(qunleashed_hn_sse2   ${MP}-mmmx  ${MP}-msse2    ${MP}-mno-avx  ${MP}-mno-avx2  ${MP}-mno-avx512f)
    hn_add_variant(qunleashed_hn_avx    ${MP}-mmmx  ${MP}-msse2    ${MP}-mavx     ${MP}-mno-avx2  ${MP}-mno-avx512f)
    hn_add_variant(qunleashed_hn_avx2   ${MP}-mmmx  ${MP}-msse2    ${MP}-mavx     ${MP}-mavx2     ${MP}-mno-avx512f)
    hn_add_variant(qunleashed_hn_avx512 ${MP}-mmmx  ${MP}-msse2    ${MP}-mavx     ${MP}-mavx2     ${MP}-mavx512f)
  elseif(CMAKE_SYSTEM_PROCESSOR IN_LIST ARM64_CPUS)
    hn_add_variant(qunleashed_hn_neon)               # arm64 has a NEON baseline
  elseif(CMAKE_SYSTEM_PROCESSOR IN_LIST ARM32_CPUS)
    hn_add_variant(qunleashed_hn_neon ${MP}-mfpu=neon)
  else()
    message(STATUS "qunleashed hardnested: unknown CPU, nosimd fallback only")
  endif()
endif()

# --- The shared library (all attacks) ---------------------------------------
set(MFKEY32_SRCS
  mfkey32_bridge.c
  nested_bridge.c
  "${CRAPTO1_DIR}/bucketsort.c"
  "${CRAPTO1_DIR}/crapto1.c"
  "${CRAPTO1_DIR}/crypto1.c")

if(HN_SUPPORTED)
  list(APPEND MFKEY32_SRCS
    # hardnested orchestration + brute-force driver (compiled once, no SIMD)
    "${HARDNESTED_DIR}/cmdhfmfhard.c"
    "${HARDNESTED_DIR}/hardnested_bruteforce.c"
    # vendored lz4 (frame decompression of the bitflip tables)
    "${LZ4_DIR}/lz4.c"
    "${LZ4_DIR}/lz4hc.c"
    "${LZ4_DIR}/lz4frame.c"
    "${LZ4_DIR}/xxhash.c"
    # per-ISA SIMD engine objects
    ${HN_SIMD_OBJECTS})
endif()

add_library(qunleashed_mfkey32 SHARED ${MFKEY32_SRCS})

target_include_directories(qunleashed_mfkey32 PRIVATE "${CRAPTO1_DIR}")

if(HN_SUPPORTED)
  target_include_directories(qunleashed_mfkey32 PRIVATE ${HN_INCLUDE_DIRS})
  target_compile_definitions(qunleashed_mfkey32 PRIVATE QUNLEASHED_HAVE_HARDNESTED)
  if(NOT IS_CLANG_CL)
    target_compile_options(qunleashed_mfkey32 PRIVATE -fcommon)
  else()
    target_compile_options(qunleashed_mfkey32 PRIVATE /clang:-fcommon)
  endif()
  # hardnested uses pthreads. Present on Linux/Android/macOS/iOS and MinGW
  # (winpthreads); clang-cl on Windows additionally needs a pthreads-win32 shim.
  find_package(Threads REQUIRED)
  target_link_libraries(qunleashed_mfkey32 PRIVATE Threads::Threads)
endif()

if(IS_REAL_MSVC)
  target_compile_definitions(qunleashed_mfkey32 PRIVATE _CRT_SECURE_NO_WARNINGS LOWMEM)
  target_compile_options(
    qunleashed_mfkey32
    PRIVATE "/FI${CMAKE_CURRENT_SOURCE_DIR}/msvc_compat.h"
  )
elseif(WIN32)
  target_compile_definitions(qunleashed_mfkey32 PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
