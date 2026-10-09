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
# Every x86 variant carries a -DVBITS equal to its *hardware* vector width,
# which is not the engine's default and is worth several times the search time.
#
# The engine holds the 32-bit KeeLoq state as 32 bit-planes of VBITS lanes, so
# the default 512 needs two registers per plane on a 256-bit machine - 64 live
# vectors against the 16 the ISA has, and it spills. Measured on a Ryzen 9 3950X
# (gcc 9.4, -O3 -funroll-loops), whole-space sweep at 16 threads, each cell
# checked to still find a seed in the last block the sweep claims:
#
#            VBITS=128   256     512 (default)   1024
#   SSE2       10.9 s   16.7 s      19.6 s      26.6 s
#   AVX         7.4 s    4.3 s      17.7 s      14.2 s
#   AVX2        7.4 s    4.3 s      17.6 s      15.1 s
#
# The optimum is the native width in every row. BUILD_NOTES.md has the rest,
# including why NEON is left at the default for now and what the author measured
# on hardware he did not record.
#
# `lanes` in the result is the only runtime evidence a -DVBITS took effect, and
# the probe asserts it - see the EXPECT_LANES note in
# .github/scripts/check_faaccrack_engine.sh.
#
# Flags shared by every variant:
#
#   -Dmain=   the engine still carries the command-line entry point that keeps
#             the author's equivalence script a valid proof. A library must not
#             export it.
#   -w        the engine is machine output; formatting is destroyed, so warnings
#             about how it reads are noise. It is checked by being run, in
#             .github/scripts/check_faaccrack_engine.sh.
#             -w also covers -Wpsabi, which fires twice per variant because the
#             engine passes a 512-bit vector by value on a target without
#             avx512f. It cannot matter here: the vector type never crosses a
#             translation unit.
# Renamed per variant, because the engine is compiled once per instruction set
# and a single name would be as many definitions of one external symbol as
# there are variants. They are unreferenced either way; the name just has to be
# unique.

# Two ways to compile the engine, because neither one does both jobs.
#
# `faaccrack_add_variant` is the one to reach for. CMake compiles the source as
# part of the build, which is what supplies the cross-compilation flags - the
# target triple, the sysroot, an Android ABI's own -march and -mfpu. A bare
# invocation of the compiler never sees them: that is how the first Android
# build of this library produced host x86-64 objects and died at the link with
# "faaccrack_NEON.o is incompatible with aarch64linux".
#
# `faaccrack_add_foreign_variant` spells the compile out, and exists only for
# Windows, where the variants have to come from clang-cl while the rest of the
# target comes from MSVC and no CMake target can name a second C compiler. The
# hardnested lib keeps its own spelled-out compile inside its clang-cl branch
# for the same reason; generalising this one to every platform is what cost the
# Android build. Nothing is cross-compiled on that path, which is what makes
# the absent flags survivable there.
function(faaccrack_add_variant variant)
  add_library(faaccrack_${variant} OBJECT "${FAACCRACK_ENGINE}")
  target_compile_options(faaccrack_${variant} PRIVATE ${ARGN})
  target_compile_definitions(faaccrack_${variant}
    PRIVATE "main=faaccrack_unused_main_${variant}")
  target_include_directories(faaccrack_${variant} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${FAACCRACK_SHIM_DIR}"
  )
  set_target_properties(faaccrack_${variant} PROPERTIES
    C_STANDARD 11
    # Explicit rather than left to default: a toolchain file setting
    # CMAKE_C_EXTENSIONS OFF would compile this -std=c11, and __STRICT_ANSI__
    # hides clock_gettime and nanosleep behind glibc's feature-test macros.
    # The engine calls both.
    C_EXTENSIONS ON
    POSITION_INDEPENDENT_CODE ON
  )
  target_link_libraries(qunleashed_faaccrack PRIVATE faaccrack_${variant})
endfunction()

# Compiles the engine with ${FAACCRACK_CLANG_CL} and adds the object to the
# library. Only the clang-cl branch below calls this.
function(faaccrack_add_foreign_variant variant)
  # $<CONFIG> in the path, because the Flutter Windows build is a
  # multi-config generator: Debug, Profile and Release share one binary
  # directory, so without it all three read and write one object. The
  # hardnested lib measured what that costs - a Debug build after a Release
  # one did not recompile and linked the /MD object into a /MDd DLL.
  set(object
    "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/faaccrack_${variant}${CMAKE_C_OUTPUT_EXTENSION}")
  add_custom_command(
    OUTPUT "${object}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>"
    # The path is glued to the flag as one argument: clang-cl wants it that
    # way, and under VERBATIM any quotes written around it would be passed
    # through as part of the filename.
    COMMAND "${FAACCRACK_CLANG_CL}" ${ARGN}
      "-Dmain=faaccrack_unused_main_${variant}"
      "-I${CMAKE_CURRENT_SOURCE_DIR}"
      "-I${FAACCRACK_SHIM_DIR}"
      "/Fo${object}"
      "${FAACCRACK_ENGINE}"
    DEPENDS "${FAACCRACK_ENGINE}" "${FAACCRACK_HEADER}"
    COMMENT "faaccrack: compiling the ${variant} engine"
    VERBATIM
  )
  set_source_files_properties("${object}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
  target_sources(qunleashed_faaccrack PRIVATE "${object}")
endfunction()

# x86-64 only, and keyed on the architecture rather than on MSVC alone: the
# variants are an x86 instruction-set story, and a Windows-on-ARM build with
# clang-cl installed would otherwise be handed /arch:AVX2 for an aarch64 target.
if(MSVC AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|x86_64)$")
  # MSVC cannot compile the engine at all - it has no GCC vector extensions -
  # so clang-cl is required rather than looked up, and the build says which
  # component to install rather than failing with a wall of syntax errors.
  # clang-cl emits MSVC-ABI objects, so they link into the DLL MSVC builds.
  #
  # VSINSTALLDIR is set only inside a developer command prompt, which a Flutter
  # build is not, so that hint is dead on its own - the hardnested lib found
  # that installing the component the message recommends did nothing.
  # CMAKE_GENERATOR_INSTANCE is the VS install root the generator is already
  # using, which is where the component actually lands.
  set(FAACCRACK_PROGRAM_FILES_X86 "ProgramFiles(x86)")
  find_program(FAACCRACK_CLANG_CL
    NAMES clang-cl
    HINTS
      "${CMAKE_GENERATOR_INSTANCE}/VC/Tools/Llvm/x64/bin"
      "${CMAKE_GENERATOR_INSTANCE}/VC/Tools/Llvm/bin"
      "$ENV{VSINSTALLDIR}VC/Tools/Llvm/x64/bin"
      "$ENV{ProgramFiles}/LLVM/bin"
      "$ENV{ProgramW6432}/LLVM/bin"
      "$ENV{${FAACCRACK_PROGRAM_FILES_X86}}/LLVM/bin"
  )
  if(NOT FAACCRACK_CLANG_CL)
    message(FATAL_ERROR
      "faaccrack needs clang-cl: its engine uses vector extensions MSVC cannot "
      "compile, and unlike the hardnested library it has no scalar variant to "
      "fall back to. Install the Visual Studio \"C++ Clang tools for Windows\" "
      "component, or standalone LLVM.")
  endif()
  message(STATUS "faaccrack: building SIMD variants with ${FAACCRACK_CLANG_CL}")

  # /MD must match what CMake gives the rest of the target, or the two halves of
  # the library would want different C runtimes.
  set(faaccrack_clang_cl /nologo /c /O2 -w $<IF:$<CONFIG:Debug>,/MDd,/MD>)

  # No AVX512, for the reason the hardnested lib recorded after shipping it and
  # taking it back out: nothing here has measured it, and client Intel parts
  # downclock under 512-bit integer work - so a dispatcher that prefers it
  # unconditionally, as this one would, can be slower than AVX2 on the machines
  # most likely to run it. This engine's inner loop is pure 512-bit bitwise
  # work, so it is if anything more exposed. AVX2 is the width the engine's
  # author measured; until someone benches AVX-512 hardware, this is the honest
  # list.
  #
  # No /arch:SSE2 entry either: it is the x86-64 baseline, so clang-cl defines
  # __SSE2__ without being asked and rejects the flag as invalid for a 64-bit
  # target. The flagless compile *is* the SSE2 object.
  faaccrack_add_foreign_variant(AVX2 ${faaccrack_clang_cl} /arch:AVX2 /DVBITS=256)
  faaccrack_add_foreign_variant(AVX ${faaccrack_clang_cl} /arch:AVX /DVBITS=256)
  faaccrack_add_foreign_variant(SSE2 ${faaccrack_clang_cl} /DVBITS=128)
else()
  # -c, -fPIC and -std=gnu11 are not listed because CMake supplies all three -
  # the first from compiling at all, the other two from the properties
  # faaccrack_add_variant sets.
  set(faaccrack_engine_opts -O3 -funroll-loops -w)

  if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64|i.86|x86)$")
    # Unlike hardnested, which compiles one object at the platform baseline
    # everywhere but Windows, x86 gets the full set on every OS. The baseline on
    # x86-64 is SSE2, and the engine is several times faster with AVX2 - there
    # is no reason a Linux or Intel-Mac desktop should run the slowest variant
    # when the dispatcher can tell at runtime.
    faaccrack_add_variant(AVX2 ${faaccrack_engine_opts} -mavx2 -DVBITS=256)
    faaccrack_add_variant(AVX ${faaccrack_engine_opts} -mavx -DVBITS=256)
    faaccrack_add_variant(SSE2 ${faaccrack_engine_opts} -msse2 -DVBITS=128)
  else()
    # arm64 and armv7: NEON is the baseline, so one object is already the right
    # one and there is nothing to choose between at runtime.
    #
    # No -DVBITS here, deliberately. NEON is 128 bits, so by the rule above this
    # is the variant with the most to gain - the default is four registers per
    # plane - and it is also the one nothing in this change measured. A number
    # guessed into a mobile build is a number nobody checks: the win is real on
    # x86 because it was measured there. BUILD_NOTES.md carries the prediction
    # and what a device run would have to show.
    faaccrack_add_variant(NEON ${faaccrack_engine_opts})
  endif()
endif()
