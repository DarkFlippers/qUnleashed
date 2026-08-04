# Hardnested crack engine (vendored from Proxmark3)

Ciphertext-only attack on hardened MIFARE Classic (Meijer/Verdult 2015),
bit-sliced brute-forcer (aczid). Vendored from
`proxmark3/client/deps/hardnested/` (crapto1 comes from the existing
`../nfc-tools` submodule).

## Status
- **Crack engine ported and bench-validated.** Built all six x86 SIMD variants +
  runtime dispatch + the driver, linked against our crapto1, and ran PM3's
  `hardnested_bf_bench_data.bin` benchmark: ~1.7 Gstates/s on the AVX2 path — the
  SIMD dispatch works, not just the nosimd fallback.
- **Not yet wired into the app build, no Dart bridge yet** (next steps below).

## Files
- `hardnested_bf_core.c/.h` — bit-sliced crack kernels (`crack_states_bitsliced`,
  `bitslice_test_nonces`), compiled once per instruction set.
- `hardnested_bitarray_core.c/.h` — bit-array ops, also per-instruction-set.
- `hardnested_bruteforce.c/.h` — driver (`brute_force_bs`, `brute_force_benchmark`,
  `verify_key`) + the runtime dispatcher (in the `NOSIMD_BUILD` object).
- `hardnested_tables.c` — bitflip/sum-property table code (used by the
  orchestration, below).
- `hn_compat.h` — shim replacing PM3 client deps (ui/comms/fileutils/util_posix):
  `PrintAndLogEx` no-op, `msclock`, `num_CPUs`, `searchFile`, progress callbacks.

## Adaptations vs upstream
- `hardnested_bf_core.c`: `#include "ui.h"` → `hn_compat.h`.
- `hardnested_bruteforce.c`: dropped the PM3 includes
  (common/proxmark3/cmdhfmfhard/ui/util/util_posix/fileutils/pm3_cmd), added
  `hn_compat.h`. Everything else is upstream.

## Build recipe (validated with MinGW gcc 13)
`bf_core.c` and `bitarray_core.c` are compiled **once per instruction set**, each
producing suffixed symbols (`_NOSIMD`/`_MMX`/`_SSE2`/`_AVX`/`_AVX2`/`_AVX512` on
x86; `_NEON` on ARM). The dispatcher lives in the `NOSIMD_BUILD` object and picks
the best at runtime, so **all** variants for the target arch must be linked.
`bruteforce.c` is compiled once (no SIMD). Include paths: this dir + the crapto1
dir and its parent.

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
   CMake and the macOS/iOS Xcode project (or a dedicated CMake target), gated on
   `CMAKE_SYSTEM_PROCESSOR`.
2. Orchestration: port the offline-solve path from `cmdhfmfhard.c` (sum-property
   analysis, `init_bitflip_bitarrays`, statelist generation → `brute_force_bs`),
   stripping its PM3 deps like the driver above.
3. Tables: bundle the ~9.2 MB `hardnested_tables/*.lz4` (351 files) as Flutter
   assets + an lz4 decompressor, fed to the orchestration.
4. Bridge + Dart FFI/isolate + a `.nested.log` hardnested-line parser + UI.
5. Validate end-to-end against a real hardnested capture (pending sample).
