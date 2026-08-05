//-----------------------------------------------------------------------------
// qUnleashed host-side hardnested bridge (implemented in cmdhfmfhard.c).
//
// The Flipper firmware only collects nonces (into .nested.log). The complete
// hardnested attack (Meijer/Verdult ciphertext-only cryptanalysis) runs here on
// the companion-app host, over these two entry points.
//-----------------------------------------------------------------------------
#ifndef QUNLEASHED_HARDNESTED_BRIDGE_H
#define QUNLEASHED_HARDNESTED_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Point the solver at the directory that contains the hardnested_tables/ folder
// (the bundled bitflip tables the app has extracted to a writable location).
// Must be called before qunleashed_hardnested_recover(); pass NULL to clear.
void qunleashed_hardnested_set_tables_path(const char *path);

// Run the offline hardnested solve over nonces parsed from a .nested.log.
//   in_cuid  : 4-byte card UID (the "cuid" field of the log line)
//   nt_enc   : `count` encrypted nonces (32-bit each)
//   par_enc  : `count` encrypted-parity nibbles; bit3 = parity of the MSB nonce
//              byte ... bit0 = LSB byte (PM3 add_nonce convention)
//   count    : number of nonces
//   foundkey : out, recovered 48-bit key on success
// Returns 0 (PM3_SUCCESS) on recovery, negative otherwise: -19 no key found,
// -10 too few nonces to cover all 256 first bytes (or not a genuine hardened
// nonce set), -2 bad args.
int qunleashed_hardnested_recover(uint32_t in_cuid,
                                  const uint32_t *nt_enc,
                                  const uint8_t *par_enc,
                                  uint32_t count,
                                  uint64_t *foundkey);

#ifdef __cplusplus
}
#endif

#endif // QUNLEASHED_HARDNESTED_BRIDGE_H
