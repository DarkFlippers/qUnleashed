#include <stdint.h>
#include <stdlib.h>

#include "../../.sources/flipper/components/nfc/tools/impl/src/main/cpp/nfc-tools/mfkey32v2/crapto1/crapto1.h"

#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default")))
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
