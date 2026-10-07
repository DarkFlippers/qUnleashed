cmake_minimum_required(VERSION 3.13)
project(qunleashed_hardnested LANGUAGES C)

# Host-side hardnested attack. Engine + embedded XZ bitflip tables + minlzlib are
# vendored from ChameleonUltraGUI (GPL, Proxmark3-derived). Every platform builds
# one variant with its default toolchain - the compiler's own baseline, which is
# scalar on MSVC - and x86-64 Windows additionally builds per-ISA variants with
# clang-cl when it is installed, picked at runtime. clang-cl is optional; without
# it the build is the baseline one. See BUILD_NOTES.md.

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
  # Required, not preferred: qunleashed_hn_progress.h asserts its own layout
  # with _Static_assert, so a toolchain that silently decayed to C99 would turn
  # a layout guard into a compile error with a misleading message.
  C_STANDARD_REQUIRED ON
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
# x86-64 only, and keyed on the architecture rather than on MSVC: the variants
# are an x86 instruction-set story, and a Windows-on-ARM build with clang-cl
# installed would otherwise be handed /arch:AVX2 for an aarch64 target.
if(MSVC AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|x86_64)$")
  # VSINSTALLDIR is set only inside a developer command prompt, which a Flutter
  # build is not - the first hint below was dead, so installing the component
  # the message recommends did nothing. CMAKE_GENERATOR_INSTANCE is the VS
  # install root the generator is already using, which is where the component
  # actually lands.
  set(HN_PROGRAM_FILES_X86 "ProgramFiles(x86)")
  find_program(HN_CLANG_CL
    NAMES clang-cl
    HINTS
      "${CMAKE_GENERATOR_INSTANCE}/VC/Tools/Llvm/x64/bin"
      "${CMAKE_GENERATOR_INSTANCE}/VC/Tools/Llvm/bin"
      "$ENV{VSINSTALLDIR}VC/Tools/Llvm/x64/bin"
      "$ENV{ProgramFiles}/LLVM/bin"
      "$ENV{ProgramW6432}/LLVM/bin"
      "$ENV{${HN_PROGRAM_FILES_X86}}/LLVM/bin"
  )

  if(HN_CLANG_CL)
    message(STATUS "hardnested: building SIMD variants with ${HN_CLANG_CL}")
    set(HN_VARIANT_OBJECTS "")
    # No AVX512. It was in this list and is deliberately not any more: nothing
    # here has measured it, 512-bit lanes waste up to 511 states per bucket in
    # the padding loop against 63 for the baseline, and client Intel parts
    # downclock under 512-bit integer work - so preferring it unconditionally,
    # as the dispatcher would, could be slower than AVX2 on the machines most
    # likely to run this. tool/hn_bench.dart is what settles it; until someone
    # runs it on AVX512 hardware, AVX2 is the measured win and this is the
    # honest list.
    #
    # SSE2 gets no /arch: flag - it is the x86-64 baseline, so clang-cl defines
    # __SSE2__ unasked and rejects /arch:SSE2 for a 64-bit target. The unflagged
    # compile is therefore exactly the SSE2 object the dispatcher looks for.
    foreach(variant AVX2 AVX SSE2)
      if("${variant}" STREQUAL "SSE2")
        set(hn_arch_flag "")
      else()
        set(hn_arch_flag "/arch:${variant}")
      endif()
      # $<CONFIG> in the path, because the Flutter Windows build is a
      # multi-config generator: Debug, Profile and Release share one binary
      # directory, so without it all three read and write one .obj. Measured:
      # a Debug build after a Release one did not recompile and linked the /MD
      # object into a /MDd DLL - two C runtimes, two heaps, and an
      # _aligned_free that frees from the wrong one.
      set(hn_obj "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/hn_bf_core_${variant}.obj")
      add_custom_command(
        OUTPUT "${hn_obj}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>"
        COMMAND "${HN_CLANG_CL}"
          /nologo /c /O2
          # Must match what CMake gives the rest of this target, or the two
          # halves of the library would want different C runtimes.
          $<IF:$<CONFIG:Debug>,/MDd,/MD>
          ${hn_arch_flag}
          /DQUNLEASHED_HN_SIMD_VARIANTS
          /D_CRT_SECURE_NO_WARNINGS
          # The same force-include every other source in this target gets, so
          # the vendored crapto1 symbols are renamed consistently.
          "/FI${CMAKE_CURRENT_SOURCE_DIR}/hn_namespace.h"
          "/I${CMAKE_CURRENT_SOURCE_DIR}"
          "/I${CMAKE_CURRENT_SOURCE_DIR}/hardnested"
          "/Fo${hn_obj}"
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.c"
        # Every header the translation unit reaches, spelled out: a custom
        # command has no depfile, so what is not listed here is not noticed.
        # qunleashed_hn_progress.h is the one that matters - it declares the
        # struct both halves of the library map, so a stale variant object
        # reads the old field offsets with no link error and the progress bar
        # or Stop quietly stops working.
        DEPENDS
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.c"
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bf_core.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/hardnested/hardnested_bruteforce.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/qunleashed_hn_progress.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/crapto1.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/parity.h"
          "${CMAKE_CURRENT_SOURCE_DIR}/ui.h"
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
    # NOTICE, not STATUS: Flutter filters STATUS out of a build, so the old
    # message reached nobody. The figure is the measured one - 4543 s against
    # 68 s on the same card and log - not the "~8x" the width difference alone
    # would predict, because the scalar variant also carried a width bug.
    message(NOTICE
      "hardnested: clang-cl not found - the brute force will run the scalar "
      "variant, which measured ~67x slower than AVX2 on the same card. Install "
      "the Visual Studio \"C++ Clang tools for Windows\" component, or LLVM, "
      "for the fast build.")
  endif()
endif()
