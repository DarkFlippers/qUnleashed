# Hardnested attack (host-side)

Ciphertext-only attack on hardened MIFARE Classic (Meijer/Verdult 2015). The
Flipper firmware only collects nonces into `.nested.log`; the whole attack runs
here on the companion-app host, built into the `qunleashed_hardnested` FFI lib.

## Origin
Vendored from **[ChameleonUltraGUI](https://github.com/GameTec-live/ChameleonUltraGUI)**
(`chameleonultragui/src`), a shipping cross-platform Flutter app that solves
hardnested host-side. Its engine is a Proxmark3 fork (GPL) made **MSVC-compatible**,
so it builds with the default toolchain on every platform - **no clang-cl needed**.
`minlzlib/` is Alex Ionescu's minimal XZ decoder (MIT, see `minlzlib/LICENSE`).
The small Proxmark3 support files the engine needs (logging, timing, endian /
`ARRAYLEN` helpers - `commonutil`, `ui`, `util`, `util_posix`, `common`, `ansi`)
sit alongside the engine sources here; each keeps its Proxmark3 provenance header
linking the upstream repo (they were previously under a confusing `pm3/` folder).

We deliberately chose this over a from-scratch PM3 port: the PM3 engine uses
GCC/Clang vector extensions MSVC can't compile, which would have forced clang-cl
on Windows. This fork adds an `#ifdef _MSC_VER` scalar fallback instead.

## Why no clang / how the SIMD works
`hardnested_bf_core.c` selects the bitslice type by compiler:
- GCC/Clang: `__attribute__((vector_size))` → baseline SIMD (SSE2 on x86, NEON on
  ARM). ~4× the scalar path.
- MSVC (`_MSC_VER`): plain `uint32_t` scalar (32-wide). Compiles cleanly; slower.

It is a **single variant** (no per-ISA AVX2 dispatch), so the build is simple and
portable. Trade-off: Windows-MSVC runs scalar (~8× slower than AVX2), fine for a
companion app; Linux/macOS/Android get baseline SIMD. Fast AVX2 would require
clang-cl on Windows and per-ISA object libraries - intentionally not done.

## Tables
The ~319 bitflip state tables are **embedded** (XZ-compressed) in
`hardnested/tables.c` and decompressed in-memory by minlzlib via
`get_bitflip()`. No Flutter assets, no first-run extraction, no runtime path
wiring - the lib is self-contained.

## Bridge (the FFI entry)
`qunleashed_hardnested_bridge.c` exports:
```c
int qunleashed_hardnested_recover(uint32_t cuid, const uint32_t *nt_enc,
                                  const uint8_t *par_enc, uint32_t count,
                                  uint64_t *foundkey);   // 0 = ok
```
It packs the parallel `nt_enc[]`/`par_enc[]` arrays into the PM3 in-memory binary
nonce format (`[cuid:4][blk:1][keyty:1]` then `[nt1:4][nt2:4][par:1]` records)
and calls the engine's `mfnestedhard(..., nonces, length)`. Keeping the array API
means the Dart side just passes the parsed nonces; `par_enc[i]` is the 4-bit
encrypted-parity nibble (bit3 = MSB nonce byte … bit0 = LSB).

## Threads
Real pthreads on Linux/Android/macOS/iOS and MinGW (winpthreads); the bundled
`pthread_shim.h` (Win32 SRWLOCK + `_beginthreadex`) on clang-cl/MSVC, which ship
no `<pthread.h>`. `hardnested.c` and `hardnested_bruteforce.c` include it through
a `_WIN32 && !__MINGW32__` guard.

## Build (validated with MinGW gcc 13)
`CMakeLists.txt` builds the `qunleashed_hardnested` shared lib (engine + minlzlib
+ bridge), single variant, `-O3` on GCC/Clang. Validated: the built DLL recovers
a known key from synthetic nonces via the bridge (~12 s incl. table decompress),
loading 319 embedded tables through minlzlib - no external files.

`_In_=` is defined only under MinGW (which defines `_WIN32` but lacks MSVC's
`sal.h` that minlzlib references); real MSVC has `sal.h`, Linux/macOS don't take
the `_WIN32` path.

Note: this lib bundles its own crapto1 (from the CUG fork), identical to the
`nfc-tools` submodule crapto1 used by `qunleashed_mfkey32`. On Windows/Linux/
Android they are separate DLLs/SOs (no clash); on Apple everything links into one
Runner binary, so `hn_namespace.h` renames this lib's 17 crapto1 symbols with an
`hn_` prefix (force-included via the CMake and the podspec). The exported bridge
is untouched.

## Build wiring (all platforms)
`lib/modules/cpp/CMakeLists.txt` builds both `qunleashed_mfkey32` and
`qunleashed_hardnested`. Windows/Linux runner CMake `add_subdirectory` it (and
bundle both libraries); Android's gradle `externalNativeBuild` points at it.
Apple (macOS/iOS) uses a development **CocoaPods pod** in `apple/`
(`qunleashed_hardnested.podspec` + `qunleashed_hardnested_unity.c` - a forwarder
that `#include`s the shared sources into one TU, with `hn_namespace.h`
force-included); both `ios/Podfile` and `macos/Podfile` reference it. Dart loads
the symbols via `DynamicLibrary.process()` on Apple (the pod links into Runner).

Validated (MinGW gcc 13): the top-level CMake builds both libs and exports their
bridges; the Apple unity forwarder compiles as one TU and recovers a known key.
The **podspec/Podfile Ruby glue is only exercised by an Xcode build** (no Mac
here) - the next tagged release's macOS/iOS CI job (`auto-release.yml`) is the
check. Likely first-adjustment points if it fails: the pod's `HEADER_SEARCH_PATHS`
/ `OTHER_CFLAGS` in the podspec, or the `:path` in the Podfiles.

## Remaining work
1. **Dart**: a `.nested.log` hardnested-line parser + routing (by nonce count)
   + UI. `hardnested_recoverer.dart` + the FFI already work; deferred until a
   real hardnested capture confirms the log line format / `par_enc` mapping.
2. End-to-end validation against a real hardnested capture.
