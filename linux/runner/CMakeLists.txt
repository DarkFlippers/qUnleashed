cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

add_subdirectory("../../lib/modules/cpp" "${CMAKE_CURRENT_BINARY_DIR}/cpp")

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} qunleashed_mfkey32)
add_dependencies(${BINARY_NAME} qunleashed_hardnested)
add_dependencies(${BINARY_NAME} qunleashed_faaccrack)

# Its own variable, not `PLUGIN_BUNDLED_LIBRARIES`, which is what this used to
# append to. That does not survive: `flutter/generated_plugins.cmake` carries a
# bare `set(PLUGIN_BUNDLED_LIBRARIES)` before its own loops, which clears it,
# and the parent includes that file *after* this subdirectory - so all three
# libraries were dropped before the install step read the list, and no Linux
# release has ever carried them. `DynamicLibrary.open` then fails and MIFARE and SubGHz seed
# recovery raise `NativeEngineUnavailable`, which is exactly the "packaging
# fault" its doc comment was written for.
#
# Windows never had this because `windows/runner/CMakeLists.txt` copies the
# three DLLs into the bundle with a POST_BUILD command instead of going through
# that list. The same trick does not work here: this runner's output goes to
# `intermediates_do_not_run`, so the install step is the only route into the
# bundle on Linux.
set(QUNLEASHED_FFI_LIBRARIES
  $<TARGET_FILE:qunleashed_mfkey32>
  $<TARGET_FILE:qunleashed_hardnested>
  $<TARGET_FILE:qunleashed_faaccrack>
  PARENT_SCOPE
)
