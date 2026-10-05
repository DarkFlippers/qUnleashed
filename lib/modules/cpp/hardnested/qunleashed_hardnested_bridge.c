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
#include <stdio.h>
#include <stdlib.h>

#include "hardnested.h"  // mfnestedhard
#include "hardnested/tables.h"  // get_bitflip, for the memory figure below
#include "qunleashed_hn_progress.h"

// For qunleashed_hn_available_bytes only.
#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include <os/proc.h>  // os_proc_available_memory
#endif
#endif

// Kept identical to qunleashed_mfkey32's copy, which carries the explanation -
// see lib/modules/cpp/mfkey32/nested_bridge.c. `used` costs nothing in the
// framework this lib ships as on Apple, and the two macros not drifting is
// worth more than the one line saved.
#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default"), used))
#endif

// Bytes the engine holds for an attack's whole duration: one decompressed
// bitflip state table per entry the vendored table set actually carries, the
// size init_bitflip_bitarrays() allocates them at.
//
// Walked rather than written down. The count is a property of tables.c, which
// is vendored and will change when it is next updated; a constant here would go
// quietly wrong, and the whole point of the figure is that the caller trusts it.
//
// A floor, not a total: the sum-property bitarrays and the candidate statelists
// are on top of this, and vary with the nonce set. The caller adds its own
// margin - see hardnestedMemoryVerdict in hardnested_recoverer.dart.
QUNLEASHED_EXPORT uint64_t qunleashed_hn_table_bytes(void) {
  const uint64_t per_table = (uint64_t)sizeof(uint32_t) * ((1u << 19) + 1u);
  uint64_t tables = 0;
  for (uint16_t bitflip = 0x001; bitflip < 0x400; bitflip++) {
    if (get_bitflip(EVEN_STATE, bitflip).input_buffer != NULL) tables++;
    if (get_bitflip(ODD_STATE, bitflip).input_buffer != NULL) tables++;
  }
  return tables * per_table;
}

// What the OS says is still available, or 0 for "no answer".
//
// 0 must be read as "go ahead", never as "none": a gate that refuses on a
// figure it could not get would block attacks that would have worked, and the
// behaviour without any gate is what shipped until now.
//
// Only the platforms that overcommit are answered, because they are the ones
// where the engine's own out-of-memory handling never runs - malloc succeeds
// and the kernel kills the process when XzDecode first touches the pages.
QUNLEASHED_EXPORT uint64_t qunleashed_hn_available_bytes(void) {
#if defined(_WIN32)
  MEMORYSTATUSEX status;
  status.dwLength = sizeof(status);
  if (!GlobalMemoryStatusEx(&status)) {
    return 0;
  }
  return (uint64_t)status.ullAvailPhys;
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
  // What is left of *this process's* allowance, which is the figure iOS kills
  // against - not a system-wide free count, which would be far too optimistic
  // on a device that gives an app a fraction of RAM.
  return (uint64_t)os_proc_available_memory();
#else
  // macOS has no per-process allowance to ask about, and a desktop is not where
  // this fails. "No answer" rather than a guess from vm_stat.
  return 0;
#endif
#elif defined(__linux__)
  // MemAvailable: the kernel's own estimate of what can be had without
  // swapping, which is a better question than MemFree. Android is a __linux__
  // target and is where this matters most.
  FILE *meminfo = fopen("/proc/meminfo", "r");
  if (meminfo == NULL) {
    return 0;
  }
  char line[256];
  unsigned long long kb = 0;
  while (fgets(line, sizeof(line), meminfo) != NULL) {
    if (sscanf(line, "MemAvailable: %llu kB", &kb) == 1) {
      break;
    }
  }
  fclose(meminfo);
  return (uint64_t)kb * 1024u;
#else
  return 0;
#endif
}

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
