cmake_minimum_required(VERSION 3.13)
project(qunleashed_native LANGUAGES C)

# Native FFI libraries for the MIFARE key-recovery tools. Each subdirectory is a
# self-contained shared library the app loads via dart:ffi:
#   qunleashed_mfkey32    - mfkey32 + weak/static/static-encrypted nested recovery
#   qunleashed_hardnested - host-side hardnested attack (embedded bitflip tables)
#   qunleashed_faaccrack  - SubGHz rolling-code seed recovery (generated engine)
# TEMPORARY, remove before merge.
message(STATUS "QU-DEBUG lib/modules/cpp: C_FLAGS_RELEASE='${CMAKE_C_FLAGS_RELEASE}' COMPILE_OPTIONS='${CMAKE_C_FLAGS}'")
get_directory_property(_qu_dir_opts COMPILE_OPTIONS)
message(STATUS "QU-DEBUG lib/modules/cpp: dir COMPILE_OPTIONS='${_qu_dir_opts}'")

add_subdirectory(mfkey32)
add_subdirectory(hardnested)
add_subdirectory(faaccrack)
