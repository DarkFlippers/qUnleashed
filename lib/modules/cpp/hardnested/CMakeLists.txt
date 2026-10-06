cmake_minimum_required(VERSION 3.13)
project(qunleashed_hardnested LANGUAGES C)

# Host-side hardnested attack. Engine + embedded XZ bitflip tables + minlzlib are
# vendored from ChameleonUltraGUI (GPL, Proxmark3-derived). Single SIMD variant
# (baseline SSE2/NEON on GCC/Clang, scalar on MSVC) so it builds with the default
# toolchain on every platform - no clang-cl required. See BUILD_NOTES.md.

add_library(qunleashed_hardnested SHARED
  qunleashed_hardnested_bridge.c
  qunleashed_hn_progress.c
  hardnested.c
  crapto1.c
  crypto1.c
  bucketsort.c
  parity.c
  hardnested/hardnested_bf_core.c
  hardnested/hardnested_bf_dispatch.c
  hardnested/hardnested_bitarray_core.c
  hardnested/hardnested_bruteforce.c
  hardnested/tables.c
  commonutil.c
  ui.c
  util.c
  util_posix.c
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
)

set_target_properties(qunleashed_hardnested PROPERTIES
  C_STANDARD 11
  POSITION_INDEPENDENT_CODE ON
)

# Force-include hn_namespace.h into every source so the vendored crapto1 symbols
# are renamed (see the header) - lets this lib coexist with qunleashed_mfkey32's
# crapto1 in a single binary (Apple). The Apple podspec applies the same flag.
if(MSVC)
  target_compile_options(qunleashed_hardnested PRIVATE
    "/FI${CMAKE_CURRENT_SOURCE_DIR}/hn_namespace.h")
else()
  target_compile_options(qunleashed_hardnested PRIVATE
    -include "${CMAKE_CURRENT_SOURCE_DIR}/hn_namespace.h")
endif()

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

# --- per-ISA brute-force variants --------------------------------------------
#
# The brute force is bitsliced: one block of states is tested per machine word,
# so the width of that word is the throughput. The core is written against
# MAX_BITSLICES and nothing else, which is what lets the same source be compiled
# once per instruction set - 64 bits scalar, 128 with SSE2, 256 with AVX2 - and
# the winner picked at runtime.
#
# On GCC/Clang that is one object carrying the platform baseline (SSE2 on x86,
# NEON on ARM), as before. MSVC cannot compile the vector extensions the core
# uses, so its object is the 64-bit scalar one and a Windows machine ran the
# slowest variant in the file - about eight times off AVX2, on the one platform
# where the attack is most likely to be left running for hours.
#
# clang-cl compiles that same source with the vector extensions and emits
# MSVC-ABI objects, so the variants link into the DLL MSVC builds. It is looked
# up rather than required: without it this falls back to exactly what shipped
# before, so nobody's build breaks for want of a component - it is just slow.
# Install it with the VS "C++ Clang tools for Windows" component, or standalone
# LLVM.
if(MSVC)
  find_program(HN_CLANG_CL
    NAMES clang-cl
    HINTS
      "$ENV{VSINSTALLDIR}VC/Tools/Llvm/x64/bin"
      "$ENV{ProgramFiles}/LLVM/bin"
      "$ENV{ProgramW6432}/LLVM/bin"
      "$ENV{ProgramFiles(x86)}/LLVM/bin"
  )

  if(HN_CLANG_CL)
    message(STATUS "hardnested: building SIMD variants with ${HN_CLANG_CL}")
    set(HN_VARIANT_OBJECTS "")
    # AVX512 is included because the dispatcher only reaches it on a CPU *and*
    # an OS that both say so; machines without it never load that object.
    foreach(variant AVX512 AVX2 AVX SSE2)
      set(hn_obj "${CMAKE_CURRENT_BINARY_DIR}/hn_bf_core_${variant}.obj")
      add_custom_command(
        OUTPUT "${hn_obj}"
        COMMAND "${HN_CLANG_CL}"
          /nologo /c /O2
          # Must match what CMake gives the rest of this target, or the two
          # halves of the library would want different C runtimes.
          $<IF:$<CONFIG:Debug>,/MDd,/MD>
          "/arch:${variant}"
          /DQUNLEASHED_HN_SIMD_VARIANTS
          /D_CRT_SECURE_NO_WARNINGS
          # The same force-include every other source in this target gets, so
          # the vendored crapto1 symbols are renamed consistently.
          "/FI${CMAKE_CURRENT_SOURCE_DIR}/hn_namespace.h"
          "/I${CMAKE_CURRENT_SOURCE_DIR}"
          "/I${CMAKE_CURRENT_SOURCE_DIR}/hardnested"
          "/Fo${hn_obj}"
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.c"
        DEPENDS
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.c"
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/hn_namespace.h"
        COMMENT "hardnested: compiling the ${variant} brute force"
        VERBATIM
      )
      set_source_files_properties("${hn_obj}" PROPERTIES
        EXTERNAL_OBJECT TRUE
        GENERATED TRUE
      )
      list(APPEND HN_VARIANT_OBJECTS "${hn_obj}")
    endforeach()

    target_sources(qunleashed_hardnested PRIVATE ${HN_VARIANT_OBJECTS})
    # Tells the dispatcher that the variants exist and may be selected. Without
    # it the dispatcher cannot even name them: MSVC's own predefined macros
    # describe what *it* was told to target, which says nothing about objects a
    # second toolchain produced.
    target_compile_definitions(qunleashed_hardnested PRIVATE QUNLEASHED_HN_SIMD_VARIANTS)
  else()
    message(STATUS
      "hardnested: clang-cl not found - the brute force will run the scalar "
      "variant, which is several times slower than AVX2. Install the VS "
      "\"C++ Clang tools for Windows\" component for the fast build.")
  endif()
endif()
