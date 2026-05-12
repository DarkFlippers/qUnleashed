cmake_minimum_required(VERSION 3.13)
project(qunleashed_mfkey32 LANGUAGES C)

set(NFC_TOOLS_DIR
  "${CMAKE_CURRENT_SOURCE_DIR}/../nfc-tools"
)
set(CRAPTO1_DIR "${NFC_TOOLS_DIR}/mfkey32v2/crapto1")

add_library(qunleashed_mfkey32 SHARED
  mfkey32_bridge.c
  "${CRAPTO1_DIR}/bucketsort.c"
  "${CRAPTO1_DIR}/crapto1.c"
  "${CRAPTO1_DIR}/crypto1.c"
)

target_include_directories(qunleashed_mfkey32 PRIVATE "${CRAPTO1_DIR}")

if(MSVC)
  target_compile_definitions(qunleashed_mfkey32 PRIVATE _CRT_SECURE_NO_WARNINGS LOWMEM)
  target_compile_options(
    qunleashed_mfkey32
    PRIVATE "/FI${CMAKE_CURRENT_SOURCE_DIR}/msvc_compat.h"
  )
elseif(WIN32)
  target_compile_definitions(qunleashed_mfkey32 PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
