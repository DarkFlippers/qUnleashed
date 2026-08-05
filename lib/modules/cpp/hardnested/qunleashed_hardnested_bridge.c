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

#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default")))
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
// Returns 0 on success, negative otherwise (-2 bad args, -1 OOM, -10 no key).
QUNLEASHED_EXPORT int qunleashed_hardnested_recover(uint32_t in_cuid,
                                                    const uint32_t *nt_enc,
                                                    const uint8_t *par_enc,
                                                    uint32_t count,
                                                    uint64_t *foundkey) {
  if (nt_enc == NULL || par_enc == NULL || foundkey == NULL || count < 2) {
    return -2;
  }

  // PM3 binary nonce buffer: [cuid:4][trgBlock:1][trgKeyType:1] then, per
  // 9-byte record, [nt_enc1:4][nt_enc2:4][par:1] where par = (par1<<4)|par2.
  uint32_t pairs = count / 2;
  uint32_t len = 6 + pairs * 9;
  uint8_t *buf = (uint8_t *)malloc(len);
  if (buf == NULL) return -1;

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
  return (res == 1 && fk != 0) ? 0 : -10;
}
