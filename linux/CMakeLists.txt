# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "qunleashed")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.darkflippers.qunleashed")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# === Debug information in Release ===
#
# Not Flutter's. The Release configuration compiles at `-O3` with no `-g`, so
# the binaries carry a symbol table and unwind info but no DWARF -
# `sentry-cli debug-files check` on one reports `symtab, unwind` where a `-g`
# build reports `symtab, debug, unwind`. The upload step is not failing and the
# bundle is not empty; what Sentry receives simply cannot name a file or a
# line, and an inlined frame is gone entirely. Same shortfall #310 found on
# Windows, where the MSVC Release default wrote no PDB at all.
#
# Set on the configuration-level variable rather than inside
# `APPLY_STANDARD_SETTINGS`, because that function reaches only the targets
# that call it. This reaches every target in the tree, which is the point: the
# plugin shared objects are most of what a native crash is.
#
# `enable_language(C)` first, and it is not decoration. `project()` above
# declares `LANGUAGES CXX`, so without this line C is still unenabled here and
# `${CMAKE_C_FLAGS_RELEASE}` expands to **nothing** - the append would not
# extend the defaults, it would replace them with ` -g` and shadow the cache
# entry that `lib/modules/cpp`'s own `project(... LANGUAGES C)` writes later.
# All three C libraries would then lose `-DNDEBUG`, and `qunleashed_mfkey32`
# would lose `-O3` outright - hardnested and faaccrack's engine objects add
# `-O3` themselves, so they keep it. They are the MIFARE and SubGHz
# bruteforce engines, where throughput is the point.
#
# None of that shows up in a warm build directory, where the cache entry
# already exists and the append lands on it correctly. It only appears on a
# clean checkout - which is every CI run.
enable_language(C)

# `-g` does not change code generation; `-O3` still applies. What it changes is
# the size of the output, and on ELF that size ships - the DWARF goes *into*
# the `.so`, where Windows would have written a separate PDB. `build/linux.sh`
# therefore packages a stripped copy and leaves this bundle, the one the upload
# step reads, alone. That strip is the thing to keep if this ever moves.
#
# If this block ever stops applying, `build/linux.sh` refuses to package the
# build rather than quietly shipping one Sentry cannot read.
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -g")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -g")


# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# The three `lib/modules/cpp` libraries, which are not Flutter plugins and so
# are not in the list above. They used to append to it from
# `runner/CMakeLists.txt`, but `flutter/generated_plugins.cmake` clears that
# variable and is included after this subdirectory - so they were silently
# dropped and no Linux release has ever shipped them. See the note beside
# `QUNLEASHED_FFI_LIBRARIES` in `runner/CMakeLists.txt`.
#
# Empty means `runner/CMakeLists.txt` stopped setting it, or something cleared
# it the way `generated_plugins.cmake` clears the variable this replaced. A
# `foreach` over nothing is CMake's quietest construct - it would configure,
# build and install silently, and only `build/linux.sh` would notice, in a job
# that runs on no pull request. Failing here puts it in front of anyone who
# runs `flutter build linux` at all.
if(NOT QUNLEASHED_FFI_LIBRARIES)
  message(FATAL_ERROR
    "QUNLEASHED_FFI_LIBRARIES is empty, so the mfkey32, hardnested and "
    "faaccrack libraries would not be installed into the bundle and the app "
    "could not load them. See runner/CMakeLists.txt. (#338)")
endif()
foreach(ffi_library ${QUNLEASHED_FFI_LIBRARIES})
  install(FILES "${ffi_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(ffi_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
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
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
