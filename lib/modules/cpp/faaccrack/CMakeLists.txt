cmake_minimum_required(VERSION 3.13)
project(qunleashed_faaccrack LANGUAGES C)

# SubGHz rolling-code seed recovery. The engine is generated, obfuscated C whose
# readable source is deliberately not in this repository; the bridge and the
# dispatcher beside it are hand-written. See BUILD_NOTES.md.
#
# The engine is bitsliced, so the width of the machine word *is* the throughput,
# and it is written against a vector type and nothing else - which is what lets
# the same source be compiled once per instruction set and the winner picked at
# runtime. That is the shape hardnested uses; the difference here is that there
# is no scalar variant to fall back to, because MSVC cannot compile the vector
# extensions at all.

set(FAACCRACK_ENGINE "${CMAKE_CURRENT_SOURCE_DIR}/faaccrack.c")
set(FAACCRACK_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/faaccrack.h")
# pthread_shim.h lives with the hardnested library and is shared rather than
# copied; only the engine's clang-cl/MSVC branch includes it.
set(FAACCRACK_SHIM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../hardnested")

add_library(qunleashed_faaccrack SHARED
  faaccrack_bridge.c
  faaccrack_dispatch.c
)

target_include_directories(qunleashed_faaccrack PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${FAACCRACK_SHIM_DIR}"
)

set_target_properties(qunleashed_faaccrack PROPERTIES
  C_STANDARD 11
  POSITION_INDEPENDENT_CODE ON
)

if(WIN32)
  target_compile_definitions(qunleashed_faaccrack PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

# Tells the dispatcher that more than one engine object exists and may be
# selected between. Without it it calls the single variant this translation
# unit was compiled for - which is what the Apple pod does, since CocoaPods
# compiles one unity file per architecture. The compiler's own predefined
# macros cannot answer this: they describe what *it* was told to target, which
# says nothing about objects a second toolchain produced.
target_compile_definitions(qunleashed_faaccrack PRIVATE FAACCRACK_MULTI_VARIANT)

# Threads: real pthreads on Linux/Android/macOS/iOS and MinGW (winpthreads);
# clang-cl/MSVC use the shim, which needs no extra library.
if(NOT (WIN32 AND NOT MINGW))
  find_package(Threads REQUIRED)
  target_link_libraries(qunleashed_faaccrack PRIVATE Threads::Threads)
endif()

# --- the per-ISA engine objects ----------------------------------------------
#
# Flags shared by every variant:
#
#   -Dmain=   the engine still carries the command-line entry point that keeps
#             the author's equivalence script a valid proof. A library must not
#             export it.
#   -w        the engine is machine output; formatting is destroyed, so warnings
#             about how it reads are noise. It is checked by being run, in
#             .github/scripts/check_faaccrack_engine.sh.
#   -Wno-psabi (GCC/Clang, below AVX-512) passing a 512-bit vector by value has
#             an unstable ABI without avx512f. It cannot matter here - the
#             vector type never crosses a translation unit - and the warning
#             fires twice per variant otherwise. Folded into -w above, and named
#             here because it is the one that looks alarming.
# Per variant, because the engine is compiled once per instruction set and a
# single renamed main would be four definitions of one external symbol.
# They are unreferenced either way; the name just has to be unique.

# Compiles the engine once for `variant`, with `flags`, and adds the object to
# the library. One function so the three toolchain paths below cannot drift in
# what they pass.
function(faaccrack_add_variant variant)
  set(object "${CMAKE_CURRENT_BINARY_DIR}/faaccrack_${variant}${CMAKE_C_OUTPUT_EXTENSION}")
  # Assembled per toolchain rather than from a shared prefix variable: clang-cl
  # wants the path glued to the flag as one argument, and under VERBATIM any
  # quotes written around it are passed through as part of the filename.
  if(MSVC)
    set(output_args "/Fo${object}")
  else()
    set(output_args -o "${object}")
  endif()
  add_custom_command(
    OUTPUT "${object}"
    COMMAND ${FAACCRACK_VARIANT_CC} ${ARGN}
      "-Dmain=faaccrack_unused_main_${variant}"
      "-I${CMAKE_CURRENT_SOURCE_DIR}"
      "-I${FAACCRACK_SHIM_DIR}"
      ${output_args}
      "${FAACCRACK_ENGINE}"
    DEPENDS "${FAACCRACK_ENGINE}" "${FAACCRACK_HEADER}"
    COMMENT "faaccrack: compiling the ${variant} engine"
    VERBATIM
  )
  set_source_files_properties("${object}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
  target_sources(qunleashed_faaccrack PRIVATE "${object}")
endfunction()

if(MSVC)
  # MSVC cannot compile the engine at all - it has no GCC vector extensions -
  # so clang-cl is required rather than looked up, and the build says which
  # component to install rather than failing with a wall of syntax errors.
  # clang-cl emits MSVC-ABI objects, so they link into the DLL MSVC builds.
  find_program(FAACCRACK_CLANG_CL
    NAMES clang-cl
    HINTS
      "$ENV{VSINSTALLDIR}VC/Tools/Llvm/x64/bin"
      "$ENV{ProgramFiles}/LLVM/bin"
      "$ENV{ProgramW6432}/LLVM/bin"
  )
  if(NOT FAACCRACK_CLANG_CL)
    message(FATAL_ERROR
      "faaccrack needs clang-cl: its engine uses vector extensions MSVC cannot "
      "compile, and unlike the hardnested library it has no scalar variant to "
      "fall back to. Install the Visual Studio \"C++ Clang tools for Windows\" "
      "component, or standalone LLVM.")
  endif()
  message(STATUS "faaccrack: building SIMD variants with ${FAACCRACK_CLANG_CL}")

  set(FAACCRACK_VARIANT_CC "${FAACCRACK_CLANG_CL}")
  # /MD must match what CMake gives the rest of the target, or the two halves of
  # the library would want different C runtimes.
  set(faaccrack_common /nologo /c /O2 -w $<IF:$<CONFIG:Debug>,/MDd,/MD>)

  # No /arch:SSE2 entry: it is the x86-64 baseline, so clang-cl defines __SSE2__
  # without being asked and rejects the flag as invalid for a 64-bit target. The
  # flagless compile *is* the SSE2 object.
  faaccrack_add_variant(AVX512 ${faaccrack_common} /arch:AVX512)
  faaccrack_add_variant(AVX2 ${faaccrack_common} /arch:AVX2)
  faaccrack_add_variant(AVX ${faaccrack_common} /arch:AVX)
  faaccrack_add_variant(SSE2 ${faaccrack_common})
else()
  set(FAACCRACK_VARIANT_CC "${CMAKE_C_COMPILER}")
  set(faaccrack_common -c -O3 -funroll-loops -std=c11 -w -fPIC)

  if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64|i.86|x86)$")
    # Unlike hardnested, which compiles one object at the platform baseline
    # everywhere but Windows, x86 gets the full set on every OS. The baseline on
    # x86-64 is SSE2, and the engine is several times faster with AVX2 - there
    # is no reason a Linux or Intel-Mac desktop should run the slowest variant
    # when the dispatcher can tell at runtime.
    faaccrack_add_variant(AVX512 ${faaccrack_common} -mavx512f)
    faaccrack_add_variant(AVX2 ${faaccrack_common} -mavx2)
    faaccrack_add_variant(AVX ${faaccrack_common} -mavx)
    faaccrack_add_variant(SSE2 ${faaccrack_common} -msse2)
  else()
    # arm64 and armv7: NEON is the baseline, so one object is already the right
    # one and there is nothing to choose between at runtime.
    faaccrack_add_variant(NEON ${faaccrack_common})
  endif()
endif()
