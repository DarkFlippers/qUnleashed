// Xcode-only wrapper: the NOSIMD variant of the bit-array core.
// See hn_apple_bf_simd.c / ../BUILD_NOTES.md.
#define NOSIMD_BUILD
#include "../hardnested_bitarray_core.c"
