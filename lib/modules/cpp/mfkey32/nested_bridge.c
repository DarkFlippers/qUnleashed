#include <stdint.h>
#include <stdlib.h>

#include "../nfc-tools/mfkey32v2/crapto1/crapto1.h"

#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default")))
#endif

// Recover a MIFARE Classic sector key from nested nonces collected by the
// Flipper and stored in `.nested.log`.
//
// The firmware resolves the plaintext tag nonce on-device, so each sample gives
// us a *plaintext* nonce `nt` and the first keystream word `ks = nt_enc ^ nt`.
// The forward relation is `ks = crypto1_word(key_state, uid ^ nt, 0)` (verified
// against the Unleashed mfkey app), so recovery is the inverse: recover the
// state that produces `ks0` while `uid ^ nt0` is fed, roll that feed back to the
// key, and — when a second sample for the same key is available — confirm the
// candidate reproduces `ks1` from `nt1`.
//
// With two samples the key is fully determined (a wrong candidate reproduces a
// second 32-bit keystream word with probability ~2^-32). With a single sample
// the keystream under-constrains the 48-bit state, so `qunleashed_nested_enum_*`
// below exposes the whole candidate set for external filtering instead.
//
// Returns the 48-bit key value produced by PM3's crypto1_get_lfsr (the same
// layout crypto1_init consumes). *found is set to 1 when a candidate satisfied
// every sample; with a single sample that only means a candidate was produced
// (not that the key is unique) — use qunleashed_nested_enum_candidates instead.
QUNLEASHED_EXPORT uint64_t qunleashed_nested_recover_key(
    uint32_t uid,
    uint32_t nt0,
    uint32_t ks0,
    uint32_t nt1,
    uint32_t ks1,
    int32_t has_second,
    int32_t* found) {
  struct Crypto1State *s, *t;
  uint64_t key = 0;

  if (found != NULL) {
    *found = 0;
  }

  s = lfsr_recovery32(ks0, uid ^ nt0);
  if (s == NULL) {
    return 0;
  }

  for (t = s; t->odd | t->even; ++t) {
    lfsr_rollback_word(t, uid ^ nt0, 0);
    crypto1_get_lfsr(t, &key);

    if (!has_second) {
      // Single sample: return the first candidate. Callers that need a unique
      // answer must use the enumeration API and filter against a dictionary.
      if (found != NULL) {
        *found = 1;
      }
      break;
    }

    // t is positioned at the recovered key state; replay the second nonce.
    if (ks1 == crypto1_word(t, uid ^ nt1, 0)) {
      if (found != NULL) {
        *found = 1;
      }
      break;
    }
  }

  free(s);
  return key;
}

// Enumerate every candidate key consistent with a single nested sample.
//
// Writes up to `capacity` recovered keys into `out_keys` and returns the number
// of candidates found (which may exceed `capacity`, in which case the buffer was
// truncated). Intended for the static-encrypted / single-nonce path (not yet
// wired into Dart), where a per-CUID dictionary disambiguates the true key.
QUNLEASHED_EXPORT uint32_t qunleashed_nested_enum_candidates(
    uint32_t uid,
    uint32_t nt0,
    uint32_t ks0,
    uint64_t* out_keys,
    uint32_t capacity) {
  struct Crypto1State *s, *t;
  uint64_t key = 0;
  uint32_t count = 0;

  s = lfsr_recovery32(ks0, uid ^ nt0);
  if (s == NULL) {
    return 0;
  }

  for (t = s; t->odd | t->even; ++t) {
    lfsr_rollback_word(t, uid ^ nt0, 0);
    crypto1_get_lfsr(t, &key);
    if (count < capacity && out_keys != NULL) {
      out_keys[count] = key;
    }
    count++;
  }

  free(s);
  return count;
}
