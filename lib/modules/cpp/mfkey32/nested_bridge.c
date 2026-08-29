#include <stdint.h>
#include <stdlib.h>

#include "../nfc-tools/mfkey32v2/crapto1/crapto1.h"
#include "../nfc-tools/mfkey32v2/crapto1/parity.h"

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
// With two distinct samples the key is fully determined (a wrong candidate
// reproduces a second 32-bit keystream word with probability ~2^-32). With a
// single sample the keystream under-constrains the 48-bit state, so the
// candidate-enumeration APIs below expose the parity-filtered candidate set for
// external filtering (qunleashed_rf08s_reduce_pair narrows it further).
//
// Returns the 48-bit key value produced by PM3's crypto1_get_lfsr (the same
// layout crypto1_init consumes). *found is set to 1 when a candidate satisfied
// every sample; with a single sample that only means a candidate was produced
// (not that the key is unique) — use qunleashed_static_candidates instead.
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

// Enumerate the key candidates consistent with a single nested sample, filtered
// by the one leaked parity bit (the FM11RF08S "staticnested_1nt" step).
//
// The Flipper stores the transmitted parity inverted, so nt_par_enc = par ^ 0xF
// (validated against a known-key capture). Keeping only candidates whose first
// bit of the second keystream word reproduces the observed parity halves the
// set. Writes up to `capacity` keys into `out_keys` and returns the count written.
static uint32_t gen_static_candidates(
    uint32_t uid,
    uint32_t nt,
    uint32_t ks,
    uint8_t par,
    uint64_t* out_keys,
    uint32_t capacity) {
  const uint8_t nt_par_enc = par ^ 0x0F;
  struct Crypto1State *rs, *r;
  uint64_t key;
  uint32_t count = 0;

  rs = lfsr_recovery32(ks, uid ^ nt);
  if (rs == NULL) {
    return 0;
  }

  const uint8_t expected = oddparity8(nt & 0xFF);
  for (r = rs; (r->odd | r->even) && count < capacity; ++r) {
    // r is already positioned after producing ks0; feeding one more word (0)
    // yields ks2, whose top bit encrypts the last nonce byte's parity. Copy the
    // state so the rollback below only runs for candidates that pass parity.
    struct Crypto1State tmp = *r;
    const uint32_t ks2 = crypto1_word(&tmp, 0, 0);
    const uint8_t got = (uint8_t)((nt_par_enc & 1) ^ ((ks2 >> 24) & 1));
    if (expected != got) {
      continue;
    }
    lfsr_rollback_word(r, uid ^ nt, 0);
    crypto1_get_lfsr(r, &key);
    if (out_keys != NULL) {
      out_keys[count] = key;
    }
    count++;
  }

  free(rs);
  return count;
}

QUNLEASHED_EXPORT uint32_t qunleashed_static_candidates(
    uint32_t uid,
    uint32_t nt,
    uint32_t ks,
    uint32_t par,
    uint64_t* out_keys,
    uint32_t capacity) {
  return gen_static_candidates(uid, nt, ks, (uint8_t)(par & 0x0F), out_keys, capacity);
}

// --- FM11RF08S seednt16 relation (Doegox 2024) -----------------------------
// The true keyA and keyB of a sector map their (different) nonces back to the
// same 16-bit "seed" nonce, so intersecting the two candidate lists on this
// value drops many false candidates (fewer as the lists approach the 2^16 seed
// space). Adapted from PM3's staticnested_2x1nt_rf08s (logic unchanged;
// `key >> i >> 4` == upstream `key >> (i + 4)`).

static uint16_t g_s_lfsr16[1 << 16];
static uint16_t g_i_lfsr16[1 << 16];
static int g_lfsr16_ready = 0;

static void init_lfsr16(void) {
  if (g_lfsr16_ready) {
    return;
  }
  uint16_t x = 1;
  for (uint16_t i = 1; i; ++i) {
    g_i_lfsr16[(x & 0xff) << 8 | x >> 8] = i;
    g_s_lfsr16[i] = (x & 0xff) << 8 | x >> 8;
    x = x >> 1 | (x ^ x >> 2 ^ x >> 3 ^ x >> 5) << 15;
  }
  g_lfsr16_ready = 1;
}

static uint16_t prev_lfsr16(uint16_t nonce) {
  uint16_t i = g_i_lfsr16[nonce];
  i = (i == 1) ? 0xffff : i - 1;
  return g_s_lfsr16[i];
}

static uint16_t compute_seednt16(uint32_t nt32, uint64_t key) {
  static const uint8_t a[] = {0, 8, 9, 4, 6, 11, 1, 15, 12, 5, 2, 13, 10, 14, 3, 7};
  static const uint8_t b[] = {0, 13, 1, 14, 4, 10, 15, 7, 5, 3, 8, 6, 9, 2, 12, 11};
  uint16_t nt = nt32 >> 16;
  for (uint8_t i = 0; i < 14; i++) {
    nt = prev_lfsr16(nt);
  }
  int odd = 1;
  for (uint8_t i = 0; i < 6 * 8; i += 8) {
    if (odd) {
      nt ^= a[(key >> i) & 0xF];
      nt ^= b[(key >> i >> 4) & 0xF] << 4;
    } else {
      nt ^= b[(key >> i) & 0xF];
      nt ^= a[(key >> i >> 4) & 0xF] << 4;
    }
    odd ^= 1;
    for (uint8_t j = 0; j < 8; j++) {
      nt = prev_lfsr16(nt);
    }
  }
  return nt;
}

static void seednt_bitmap_set(uint8_t* bitmap, uint16_t seed) {
  bitmap[seed >> 3] |= (uint8_t)(1 << (seed & 7));
}

static int seednt_bitmap_get(const uint8_t* bitmap, uint16_t seed) {
  return (bitmap[seed >> 3] >> (seed & 7)) & 1;
}

// Generate parity-filtered candidates for a sector's keyA and keyB, then keep
// only those sharing a seednt16 partner in the other list. `out_a`/`out_b` are
// caller-allocated (>= the raw candidate count, e.g. 1<<18). On allocation
// failure the cross-filter is skipped (parity-filtered lists are returned
// unreduced) so the true key is never dropped.
//
// `truncated` (optional) reports whether either enumeration hit its capacity.
// The counts written back are post-filter, so the caller cannot infer this from
// them - and it matters for both keys, not just the capped one: a partial list
// yields a partial seed bitmap, so filtering the other list against it can drop
// the true key there too.
QUNLEASHED_EXPORT void qunleashed_rf08s_reduce_pair(
    uint32_t uid,
    uint32_t nt_a,
    uint32_t ks_a,
    uint32_t par_a,
    uint32_t nt_b,
    uint32_t ks_b,
    uint32_t par_b,
    uint64_t* out_a,
    uint32_t cap_a,
    uint32_t* count_a,
    uint64_t* out_b,
    uint32_t cap_b,
    uint32_t* count_b,
    uint32_t* truncated) {
  init_lfsr16();

  uint32_t na = gen_static_candidates(uid, nt_a, ks_a, (uint8_t)(par_a & 0x0F), out_a, cap_a);
  uint32_t nb = gen_static_candidates(uid, nt_b, ks_b, (uint8_t)(par_b & 0x0F), out_b, cap_b);

  if (truncated != NULL) {
    *truncated = (na >= cap_a || nb >= cap_b) ? 1 : 0;
  }

  uint8_t* seen_a = calloc(1 << 13, 1);
  uint8_t* seen_b = calloc(1 << 13, 1);
  if (seen_a == NULL || seen_b == NULL) {
    free(seen_a);
    free(seen_b);
    *count_a = na;
    *count_b = nb;
    return;
  }

  for (uint32_t i = 0; i < na; i++) {
    seednt_bitmap_set(seen_a, compute_seednt16(nt_a, out_a[i]));
  }
  for (uint32_t j = 0; j < nb; j++) {
    seednt_bitmap_set(seen_b, compute_seednt16(nt_b, out_b[j]));
  }

  uint32_t ka = 0;
  for (uint32_t i = 0; i < na; i++) {
    if (seednt_bitmap_get(seen_b, compute_seednt16(nt_a, out_a[i]))) {
      out_a[ka++] = out_a[i];
    }
  }
  uint32_t kb = 0;
  for (uint32_t j = 0; j < nb; j++) {
    if (seednt_bitmap_get(seen_a, compute_seednt16(nt_b, out_b[j]))) {
      out_b[kb++] = out_b[j];
    }
  }

  free(seen_a);
  free(seen_b);
  *count_a = ka;
  *count_b = kb;
}
