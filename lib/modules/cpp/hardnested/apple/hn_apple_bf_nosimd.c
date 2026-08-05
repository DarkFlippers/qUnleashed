// Xcode-only wrapper: the NOSIMD build of the bit-slice core (also carries the
// runtime SIMD dispatcher). See hn_apple_bf_simd.c / ../BUILD_NOTES.md.
#define NOSIMD_BUILD
#include "../hardnested_bf_core.c"
