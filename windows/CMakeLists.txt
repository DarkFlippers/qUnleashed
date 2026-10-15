# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(qunleashed LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "qunleashed")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

# === Debug information in Release ===
#
# Not Flutter's. CMake's MSVC defaults give the Release configuration no debug
# information at all: `CMAKE_CXX_FLAGS_RELEASE` is `/MD /O2 /Ob2 /DNDEBUG` with
# no `/Zi`, and `CMAKE_EXE_LINKER_FLAGS_RELEASE` is `/INCREMENTAL:NO` with no
# `/DEBUG`. The generated project therefore carries an empty
# `DebugInformationFormat` and `GenerateDebugInformation=false`, and **not one
# PDB is written** - not for the runner, not for a plugin DLL, not for the
# three libraries in `lib/modules/cpp`.
#
# That, and not the upload step, is why no Windows native frame has ever
# symbolicated (#310). The upload was never empty - a PE carries an export
# table and unwind info, and `sentry-cli` takes it - but export-level data is
# all it ever got for our modules, so a minidump resolved them to the nearest
# exported symbol. That is where `guard_dispatch_icall$thunk$...` came from.
# Engine frames resolve to `file:line` because Flutter *ships*
# `flutter_windows.dll.pdb`, which `sentry_dart_plugin` 3.4.0 names outright.
#
# `/DEBUG` on its own also turns `/OPT:REF` and `/OPT:ICF` off, which the
# Release default relies on, so both are named back and the shipped binary
# keeps its size. It gains only a debug directory entry naming the PDB - which
# is the record Sentry matches the uploaded PDB against.
#
# Set on the configuration-level variables rather than inside
# `APPLY_STANDARD_SETTINGS`, because that function reaches only the targets
# that call it. These reach every target in the tree, which is the point: the
# plugin DLLs and sentry-native are most of what a desktop crash is.
#
# `enable_language(C)` first, and it is not decoration. `project()` above
# declares `LANGUAGES CXX`, so without this line C is still unenabled here and
# `${CMAKE_C_FLAGS_RELEASE}` expands to **nothing** - the append would not
# extend the defaults, it would replace them with ` /Zi` and shadow the cache
# entry that `lib/modules/cpp`'s own `project(... LANGUAGES C)` writes later.
# Measured on a cold configure: the three C libraries then build Release with
# `Optimization=''`, no `/Ob2`, no `NDEBUG`, and `RuntimeLibrary=MultiThreaded`
# - unoptimized, asserts live, and against the static CRT while the clang-cl
# objects beside them stay `/MD`, which is the two-heap `_aligned_free` fault
# `hardnested/CMakeLists.txt` records having already been paid for once.
#
# None of that shows up in a warm build directory, where the cache entry
# already exists and the append lands on it correctly. It only appears on a
# clean checkout - which is every CI run.
enable_language(C)

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} /Zi")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /Zi")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE
  "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /DEBUG /OPT:REF /OPT:ICF")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE
  "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} /DEBUG /OPT:REF /OPT:ICF")

# Every *linker* PDB into the bundle directory - which is where the runner's
# would land anyway and where a plugin's would not, since a plugin builds under
# `build/windows/x64/plugins/<name>/` and only its DLL is installed here.
# Collecting them is what makes one upload cover the whole application. A
# static target's *compile* PDB is a different property
# (`CMAKE_COMPILE_PDB_OUTPUT_DIRECTORY`) and stays put; its CodeView ends up in
# the PDB of whatever links it, so there is nothing to collect.
#
# The bundle directory is deliberate rather than convenient: it is the one path
# `sentry_dart_plugin` already hands to `sentry-cli debug-files upload`
# (`flutter_debug_files.dart`, as of the 3.4.0 the lockfile pins), so nothing
# in `.github/` has to learn a new one. CMake appends the configuration to a
# plain path, so this resolves to `build/windows/x64/runner/Release`.
#
# Written out rather than reusing `BUILD_BUNDLE_DIR`, because that is defined
# a hundred lines below and `CMAKE_PDB_OUTPUT_DIRECTORY` is captured into each
# target's properties as the target is created - it has to be set before the
# first `add_subdirectory` or it reaches nothing. (A generator expression would
# also suppress the per-configuration append, so the two spellings are not
# interchangeable even where both are in scope.) What catches the two drifting
# apart is `windows.ps1` refusing to package a build whose PDBs are not here.
#
# Profile gets these PDBs too - the property is not per-configuration - and
# inherits the flags above from the block below, which copies the Release ones.
# Both are wanted: a profile build is for local work, where a symbolicated
# native frame is worth the same as it is in a crash report.
#
# These must not reach a user. `windows.ps1` excludes them from the archive and
# fails the build if one is in it anyway - that guard is the thing to keep if
# this ever moves.
set(CMAKE_PDB_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner")

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# === Where the install step puts things ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
#
# Moved **above** the plugins, which is the one line of this file that is not
# Flutter's own. Flutter's template has this block after
# `generated_plugins.cmake`, and the guard reads
# `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` - a variable CMake clears as
# soon as anything touches the prefix. `sentry_flutter` builds sentry-native,
# which includes `GNUInstallDirs`, and that is enough to clear it: the guard
# then reads false, Flutter's override is skipped, and the prefix stays at the
# Windows default of `C:/Program Files/qunleashed`. Everything compiles and the
# install step fails trying to write there - `cmake_install.cmake` names the
# path, so the symptom is three screens of MSB3073 and the cause is one cache
# line (`CMAKE_INSTALL_PREFIX:PATH=C:/Program Files/qunleashed`).
#
# Evaluating it here, before any plugin is configured, restores the guard's
# intent rather than removing it: an operator passing `-DCMAKE_INSTALL_PREFIX`
# is still honoured. `BUILD_BUNDLE_DIR` reads the `runner` target, added just
# above, and is a generator expression either way - so nothing about when it
# resolves has changed.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
