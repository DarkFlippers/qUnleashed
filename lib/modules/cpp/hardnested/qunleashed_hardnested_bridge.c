//-----------------------------------------------------------------------------
// qUnleashed host-side hardnested bridge.
//
// The Flipper firmware only collects nonces (into .nested.log); the whole
// hardnested attack (Meijer/Verdult ciphertext-only cryptanalysis) runs here on
// the companion-app host. This wraps the vendored engine's mfnestedhard(), which
// consumes the PM3 in-memory binary nonce format, behind a simple array API so
// the Dart side just passes parallel nt_enc[]/par_enc[] arrays.
//
// Engine + embedded LZ4/XZ bitflip tables + minlzlib are vendored from
// ChameleonUltraGUI (GPL, Proxmark3-derived); see BUILD_NOTES.md.
//-----------------------------------------------------------------------------
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "hardnested.h"  // mfnestedhard
#include "qunleashed_hn_progress.h"

// Kept identical to qunleashed_mfkey32's copy, which carries the explanation -
// see lib/modules/cpp/mfkey32/nested_bridge.c. `used` costs nothing in the
// framework this lib ships as on Apple, and the two macros not drifting is
// worth more than the one line saved.
#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default"), used))
#endif

static void put_be32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
}

// Recover a hardnested sector key from nonces parsed out of a .nested.log.
//   in_cuid : 4-byte card UID
//   nt_enc  : `count` encrypted nonces (32-bit each)
//   par_enc : `count` encrypted-parity nibbles (bit3 = MSB nonce byte ... bit0)
//   count   : number of nonces (>= 2; the last one is dropped if odd, since the
//             engine's reader consumes nonces in pairs)
//   foundkey: out, recovered 48-bit key on success
//   progress: optional, see qunleashed_hn_progress.h - the caller reads it
//             while this runs and sets `abort` to stop it
// Returns 0 on success, negative otherwise (-2 bad args, -1 allocation failed,
// -3 stopped, -4 another attack is running, -10 no key).
//
// -1 covers this function's own allocation only. The engine itself still calls
// exit() when it cannot allocate - from its worker threads as well as from
// setup - so an out-of-memory inside it takes the app down with nothing anyone
// can catch.
//
// The size is worth stating, because it is not an unlucky edge: every attack
// decompresses the whole bitflip state table set - 351 of them (tables.c's
// bf_zero and bf_one) at 4 * ((1 << 19) + 1) bytes each, allocated in
// hardnested.c's init_bitflip_bitarrays and freed only at the end - so ~700 MiB
// is resident for the attack's full duration on every single run.
//
// Plumbing the engine's failures through would not save the app on the
// platforms where it actually dies. Android and iOS overcommit, so malloc there
// does not return NULL at all: the kernel kills the process when XzDecode first
// touches the pages, and there is no return value to check. (Windows commits,
// so there it would help.) A probe here was tried and removed for the same
// reason - a large malloc succeeds under overcommit, so it refused nothing and
// implied a check that was not happening. What would help on mobile is a
// capacity gate in Dart before the isolate starts, measured against the figure
// the OS reports as available; that is its own change, and the one
// HardnestedOutcome.outOfMemory is currently waiting for.
QUNLEASHED_EXPORT int qunleashed_hardnested_recover(
    uint32_t in_cuid,
    const uint32_t *nt_enc,
    const uint8_t *par_enc,
    uint32_t count,
    uint64_t *foundkey,
    qunleashed_hn_progress *progress) {
  if (nt_enc == NULL || par_enc == NULL || foundkey == NULL || count < 2) {
    return -2;
  }


  // One attack at a time: a second would clobber the first's channel and send
  // its Stop nowhere. Refused rather than trusted to the caller, so the
  // invariant is a status the caller already switches on.
  if (qunleashed_hn_progress_busy()) {
    return -4;
  }
  qunleashed_hn_set_progress(progress);

  // PM3 binary nonce buffer: [cuid:4][trgBlock:1][trgKeyType:1] then, per
  // 9-byte record, [nt_enc1:4][nt_enc2:4][par:1] where par = (par1<<4)|par2.
  uint32_t pairs = count / 2;
  uint32_t len = 6 + pairs * 9;
  uint8_t *buf = (uint8_t *)malloc(len);
  if (buf == NULL) {
    qunleashed_hn_set_progress(NULL);
    return -1;
  }

  put_be32(buf, in_cuid);
  buf[4] = 0;  // trgBlockNo (unused by the offline solve)
  buf[5] = 0;  // trgKeyType (unused)
  for (uint32_t r = 0; r < pairs; r++) {
    uint8_t *rec = buf + 6 + (size_t)r * 9;
    put_be32(rec, nt_enc[2 * r]);
    put_be32(rec + 4, nt_enc[2 * r + 1]);
    rec[8] = (uint8_t)((par_enc[2 * r] << 4) | (par_enc[2 * r + 1] & 0x0f));
  }

  uint64_t fk = 0;
  int res = mfnestedhard(0, 0, NULL, 0, 0, NULL, false, false, false, &fk,
                         (char *)buf, len);
  free(buf);
  *foundkey = fk;
  const int stopped = progress != NULL && progress->abort != 0;
  qunleashed_hn_set_progress(NULL);
  if (res == 1 && fk != 0) {
    return 0;
  }
  // Told apart from "ran and found nothing", which is the user's answer about
  // the card rather than about their own Stop.
  return stopped ? -3 : -10;
}
