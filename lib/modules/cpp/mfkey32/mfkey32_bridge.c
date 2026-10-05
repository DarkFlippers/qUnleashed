#include <stdint.h>
#include <stdlib.h>

#include "../nfc-tools/mfkey32v2/crapto1/crapto1.h"

// `used` is load-bearing on Apple, where this file links into the Runner
// executable rather than a shared library and the linker would otherwise drop a
// global no Swift or Obj-C calls - see the note on the same macro in
// nested_bridge.c.
#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default"), used))
#endif

QUNLEASHED_EXPORT uint64_t qunleashed_mfkey32_recover_key(
    uint32_t uid,
    uint32_t nt0,
    uint32_t nr0,
    uint32_t ar0,
    uint32_t nt1,
    uint32_t nr1,
    uint32_t ar1,
    int32_t* found) {
  struct Crypto1State *s, *t;
  uint64_t key = 0;
  uint32_t p64 = prng_successor(nt0, 64);
  uint32_t p64b = prng_successor(nt1, 64);

  if (found != NULL) {
    *found = 0;
  }

  s = lfsr_recovery32(ar0 ^ p64, 0);
  if (s == NULL) {
    return 0;
  }

  for (t = s; t->odd | t->even; ++t) {
    lfsr_rollback_word(t, 0, 0);
    lfsr_rollback_word(t, nr0, 1);
    lfsr_rollback_word(t, uid ^ nt0, 0);
    crypto1_get_lfsr(t, &key);

    crypto1_word(t, uid ^ nt1, 0);
    crypto1_word(t, nr1, 1);
    if (ar1 == (crypto1_word(t, 0, 0) ^ p64b)) {
      if (found != NULL) {
        *found = 1;
      }
      break;
    }
  }

  free(s);
  return key;
}

// Returns the index of the first key in `keys` that already opens this nonce,
// or -1.
//
// Cracking a key the user already has is the single largest waste in a run: the
// nonce logs are never cleared, so every run re-attacks every nonce ever
// collected. One crypto1 pass per candidate is a rounding error next to the
// 2^19-state lfsr_recovery32 it avoids, which is why the dictionary is tried
// first rather than afterwards.
QUNLEASHED_EXPORT int32_t qunleashed_mfkey32_known_key(
    uint32_t uid,
    uint32_t nt,
    uint32_t nr,
    uint32_t ar,
    const uint64_t* keys,
    uint32_t count) {
  const uint32_t p64 = prng_successor(nt, 64);
  // Stack state, not crypto1_create: that mallocs per candidate, and this runs
  // once per dictionary key per nonce. It also removes the allocation-failure
  // branch, which could only have reported "not known" and abandoned the rest
  // of the dictionary - the one outcome this must never produce quietly.
  for (uint32_t i = 0; i < count; i++) {
    struct Crypto1State s;
    crypto1_init(&s, keys[i]);
    crypto1_word(&s, uid ^ nt, 0);
    crypto1_word(&s, nr, 1);
    if ((crypto1_word(&s, 0, 0) ^ p64) == ar) {
      return (int32_t)i;
    }
  }
  return -1;
}
