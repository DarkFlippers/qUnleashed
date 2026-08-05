// Xcode-only wrapper: compiles the bit-slice core as the target's SIMD variant
// (NEON on arm64). The CMake platforms build the per-ISA variants as separate
// object libraries instead (see ../../mfkey32/CMakeLists.txt); this wrapper
// exists because Xcode compiles each source once, so distinct TUs are needed to
// get both the SIMD and the NOSIMD builds. See ../BUILD_NOTES.md (Apple).
#include "../hardnested_bf_core.c"
