# Hardnested attack (vendored from Proxmark3)

Ciphertext-only attack on hardened MIFARE Classic (Meijer/Verdult 2015),
bit-sliced brute-forcer (aczid). Vendored from `proxmark3/client/` (crapto1
comes from the existing `../nfc-tools` submodule). The Flipper firmware only
collects nonces into `.nested.log`; the whole attack runs here on the app host.

## Status
- **Crack engine ported and bench-validated.** All six x86 SIMD variants +
  runtime dispatch + the driver, linked against our crapto1, run PM3's
  `hardnested_bf_bench_data.bin` benchmark at ~1.7 Gstates/s on the AVX2 path.
- **Orchestration + app bridge ported and validated end-to-end.** The offline
  solve from `cmdhfmfhard.c` (bitflip-table loading, sum-property analysis,
  candidate/statelist generation → `brute_force_bs`) compiles against
  `hn_compat.h` and recovers a **known key from synthetic nonces**, both via
  PM3's own `mfnestedhard(tests=1)` self-test and via our
  `qunleashed_hardnested_recover()` bridge (recovers `010320102024` from
  ~3000–6000 nonces in ~7 s incl. table load; fails gracefully below full
  first-byte coverage). Validation used MinGW gcc 13 + a synthetic nonce
  generator that mirrors PM3's `simulate_MFplus_RNG` (crapto1 primitives only).
- **Not yet wired into the app build; no Dart bridge; tables not yet bundled**
  (next steps below).

## Files
- `hardnested_bf_core.c/.h` — bit-sliced crack kernels, compiled per ISA.
- `hardnested_bitarray_core.c/.h` — bit-array ops, compiled per ISA.
- `hardnested_bruteforce.c/.h` — driver (`brute_force_bs`, `brute_force_benchmark`,
  `verify_key`) + the runtime SIMD dispatcher (in the `NOSIMD_BUILD` object).
- `cmdhfmfhard.c` — the offline solve orchestration (adapted from PM3, see
  below) + the `qunleashed_hardnested_*` bridge appended at the end.
- `hardnested_bridge.h` — public declarations of the two bridge entry points.
- `hn_compat.h` — shim replacing PM3 client deps (ui/comms/fileutils/util_posix/
  commonutil): `PrintAndLogEx` no-op, `msclock`, `num_CPUs`, `bytes_to_num`, PM3
  return codes, and a `searchFile` that resolves tables under the app-set
  `g_hardnested_tables_path` (checking existence for the raw→lz4→bz2 fallback).

The PM3 table *generator* (`hardnested_tables.c`, `write_bitflips_file`) is **not**
vendored — the solve loads the shipped precomputed tables via
`init_bitflip_bitarrays`; it never regenerates them.

## Adaptations vs upstream
- `hardnested_bf_core.c`: `#include "ui.h"` → `hn_compat.h`.
- `hardnested_bruteforce.c`: dropped PM3 includes, added `hn_compat.h`.
- `cmdhfmfhard.c`: PM3 client includes → `hn_compat.h` (crapto1/parity + engine
  headers kept); `acquire_nonces()` (device comms) stubbed to `PM3_EFAILED`;
  appended `qunleashed_hardnested_set_tables_path()` and
  `qunleashed_hardnested_recover()`. The attack itself is upstream and untouched.

## Bridge contract (`hardnested_bridge.h`)
`qunleashed_hardnested_recover(cuid, nt_enc[], par_enc[], count, &foundkey)`
runs the same solve as `mfnestedhard()`'s file path. `par_enc[i]` is a 4-bit
nibble, **bit3 = parity of the MSB nonce byte** … bit0 = LSB byte (PM3
`add_nonce` convention). Call `qunleashed_hardnested_set_tables_path(dir)` first,
pointing at the folder that contains `hardnested_tables/`.

## Build recipe (validated with MinGW gcc 13)
`bf_core.c` and `bitarray_core.c` are compiled **once per instruction set**, each
producing suffixed symbols (`_NOSIMD`/`_MMX`/`_SSE2`/`_AVX`/`_AVX2`/`_AVX512` on
x86; `_NEON` on ARM). The dispatcher lives in the `NOSIMD_BUILD` object and picks
the best at runtime, so **all** variants for the target arch must be linked.
`bruteforce.c` and `cmdhfmfhard.c` are compiled once (no SIMD). Link
`-llz4 -lbz2 -lm -lpthread`. Include paths: this dir + the crapto1 dir and its
parent.

x86 per-variant flags (mirrors PM3 `deps/hardnested.cmake`):
- nosimd: `-DNOSIMD_BUILD -mno-mmx -mno-sse2 -mno-avx -mno-avx2 -mno-avx512f`
- mmx:    `-mmmx -mno-sse2 -mno-avx -mno-avx2 -mno-avx512f`
- sse2:   `-mmmx -msse2 -mno-avx -mno-avx2 -mno-avx512f`
- avx:    `-mmmx -msse2 -mavx -mno-avx2 -mno-avx512f`
- avx2:   `-mmmx -msse2 -mavx -mavx2 -mno-avx512f`
- avx512: `-mmmx -msse2 -mavx -mavx2 -mavx512f`

ARM: build the `nosimd` object (`-DNOSIMD_BUILD`) + a `neon` object (arm64: plain;
arm32: `-mfpu=neon`).

## Remaining work
1. Build wiring: replicate the per-ISA multi-compile in `windows/linux/android`
   CMake and the macOS/iOS Xcode project (gated on `CMAKE_SYSTEM_PROCESSOR`),
   linking lz4 + bz2. Add `cmdhfmfhard.c` + `hardnested_bruteforce.c` to the
   native library and export the two bridge symbols.
2. Tables: bundle the ~9.2 MB `hardnested_tables/*.lz4` (351 files) as Flutter
   assets, extract them to a writable dir on first use, and pass that dir to
   `qunleashed_hardnested_set_tables_path()`.
3. Dart FFI + isolate + a `.nested.log` hardnested-line parser (1 sample/line,
   no `dist`; `par_enc = log_par ^ 0xF`, to confirm against a real capture) + UI.
4. Validate end-to-end against a real hardnested capture (pending sample).
