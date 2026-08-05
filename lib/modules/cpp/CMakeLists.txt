cmake_minimum_required(VERSION 3.13)
project(qunleashed_native LANGUAGES C)

# Native FFI libraries for the MIFARE key-recovery tools. Each subdirectory is a
# self-contained shared library the app loads via dart:ffi:
#   qunleashed_mfkey32    - mfkey32 + weak/static/static-encrypted nested recovery
#   qunleashed_hardnested - host-side hardnested attack (embedded bitflip tables)
add_subdirectory(mfkey32)
add_subdirectory(hardnested)
