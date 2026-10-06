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

## How the SIMD works
`hardnested_bf_core.c` is written against `MAX_BITSLICES` and nothing else, so
the same source is the 64-bit scalar loop or the 256-bit AVX2 one depending only
on what the compiler was told to target. The width and the exported function
names are both chosen from the predefined macros (`__AVX2__`, `__SSE2__`, …), in
`hardnested_bf_core.h`, so the core and the dispatcher cannot disagree.

- GCC/Clang: `__attribute__((vector_size))` → the platform baseline, one object
  (SSE2 on x86, NEON on ARM).
- MSVC: cannot compile those vector extensions, so its object is the 64-bit
  scalar loop.
- **Windows also builds AVX512/AVX2/AVX/SSE2 objects with clang-cl**, which
  emits MSVC-ABI objects that link into the DLL MSVC builds.
  `hardnested_bf_dispatch.c` picks between them at runtime with `cpuid`, and
  only after `xgetbv` says the OS preserves the wide registers.

clang-cl is **looked up, not required**: without it the build is exactly what
shipped before, just slow, and CMake says so. Install the VS *"C++ Clang tools
for Windows"* component (or standalone LLVM) for the fast build.

The dispatcher lives in its own translation unit because the core is now
compiled several times and only one copy of the function pointers may exist.

### What this replaced
A single scalar variant on Windows with the dispatch stubbed out -
`GetSIMDInstr()` returned `SIMD_NONE` unconditionally and the dispatcher
assigned `crack_states_bitsliced_NOSIMD` whatever the CPU could do. The note
here called that an intentional trade-off (~8× off AVX2), which it was while no
other variant compiled.

It also carried a bug: MSVC's `bitslice_value_t` was `uint32_t` while
`MAX_BITSLICES` was 64 and `VECTOR_SIZE` 8. `bs_ones` is built with
`memset(bytes, 0xff, VECTOR_SIZE)`, so assigning through `.value` wrote four of
eight bytes and left the rest as `malloc` found them, while
`results.bytes64[0] == 0` and `get_vector_bit()` read all eight. Half of every
block went through the crypto uninitialised and was read back out as though it
had been tested. The scalar type is `uint64_t` now, and an `#error` guards the
pairing.

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
Android they are separate DLLs/SOs (no clash). On Apple the two end up in one
process either way, so `hn_namespace.h` renames this lib's 17 crapto1 symbols
with an `hn_` prefix (force-included via the CMake and the podspec). The exported
bridge is untouched.

The renaming was written down here as avoiding a *link-time* clash in a single
Runner binary. That reason is only right if the pod links statically; with a bare
`use_frameworks!` CocoaPods builds it as a dynamic framework and there is no
link-time clash to avoid. Which of the two actually happens has never been
observed - see the validation note at the end of this file - and the renaming is
worth keeping under either, because two images exporting the same 17 names in one
process make a `dlsym` lookup ambiguous. What changed is that nothing now depends
on knowing: `.github/scripts/check_ffi_exports.sh` looks for each FFI entry point
across the main executable *and* every framework the bundle embeds.

## Build wiring (all platforms)
`lib/modules/cpp/CMakeLists.txt` builds both `qunleashed_mfkey32` and
`qunleashed_hardnested`. Windows/Linux runner CMake `add_subdirectory` it (and
bundle both libraries); Android's gradle `externalNativeBuild` points at it.
Apple (macOS/iOS) uses a development **CocoaPods pod** in `apple/`
(`qunleashed_hardnested.podspec` + `qunleashed_hardnested_unity.c` - a forwarder
that `#include`s the shared sources into one TU, with `hn_namespace.h`
force-included); both `ios/Podfile` and `macos/Podfile` reference it. Dart loads
the symbols via `DynamicLibrary.process()` on Apple, which resolves across every
image loaded into the process - so it does not matter whether the pod's code sits
in the Runner binary or in an embedded framework beside it.

`qunleashed_mfkey32` is wired differently on Apple, and deliberately not as a pod:
its sources are listed directly in `ios/Runner.xcodeproj` and
`macos/Runner.xcodeproj`, so they compile into the Runner executable. That is why
`QUNLEASHED_EXPORT` carries `used` - an executable's unreferenced globals are not
dead-strip roots, and shipping without it cost every MIFARE recovery path on both
Apple platforms. The note on the macro in `../mfkey32/nested_bridge.c` is the
canonical account.

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
