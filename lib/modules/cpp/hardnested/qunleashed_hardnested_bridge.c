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
#include "qunleashed_hn_progress.h"

// For qunleashed_hn_available_bytes only.
#if defined(__APPLE__)
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

// Bytes the engine has resident at once before it looks at a single nonce.
//
// The FFI wrapper only, so every export stays greppable in this file. What is
// counted, what is deliberately left out, and why it lives in the vendored file
// are all on the definition - qunleashed_hn_engine_peak_bytes in hardnested.c -
// and are not repeated here, because four copies of one figure's rationale is
// how one of them ends up stale after the next re-vendoring.
//
// Worth one line, as the reason this is an export rather than a constant on the
// Dart side: the answer is of the order of 1.8 GiB, and the bitflip tables
// everyone thinks of are not even the largest term in it.
QUNLEASHED_EXPORT uint64_t qunleashed_hn_peak_bytes(void) {
  return qunleashed_hn_engine_peak_bytes();
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
//
// Windows and macOS both answer 0, and that is a gap rather than a conclusion.
// They commit, so malloc does return NULL there and the engine's exit(4) does
// fire - but "fires" is not "handled": exit(4) takes the whole app down with no
// message and nothing in the log. Desktop is in fact the one place the failure
// is both detectable and still fatal, so a figure for it would turn an app that
// vanishes into a sentence someone can read.
//
// Not attempted here because neither figure can be checked from this machine,
// and the cost of getting one wrong is refusing an attack that would have
// finished - on the platforms where it currently works. If it is added:
// host_statistics64 on macOS, and on Windows the *commit* limit
// (GetPerformanceInfo), not GlobalMemoryStatusEx's ullAvailPhys, which ignores
// the pagefile and would refuse a desktop with plenty of commit charge spare.
//
// And before anyone replaces this with the device_info_plus already in
// pubspec.yaml: its availableRamSize is the wrong question on the platform that
// matters most. On iOS it is vm_stat free_count * page_size - a system-wide
// count, far too optimistic for a process the OS hands a fraction of RAM -
// where os_proc_available_memory below is this app's own remaining allowance,
// which is the figure iOS actually kills against. It would also make the gate
// an async method-channel hop.
QUNLEASHED_EXPORT uint64_t qunleashed_hn_available_bytes(void) {
#if defined(__APPLE__)
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
// allocates ~1.8 GiB before it reads a single nonce, and holds all of it at
// once. qunleashed_hn_peak_bytes above is that figure, and the note in
// hardnested.c says which five allocations it sums. The bitflip state tables
// (~702 MiB) are only the second largest, and they are the one term freed
// partway through - the rest stands until the attack ends.
//
// Plumbing the engine's failures through would not save the app on the
// platforms where it actually dies. Android and iOS hand out address space
// lazily, so on 64-bit malloc does not return NULL: the kernel kills the
// process when XzDecode first touches the pages, and there is no return value
// to check. (A 32-bit armeabi-v7a build can still exhaust its ~3 GiB of address
// space and see NULL; Windows and macOS commit, so there it would help - which
// is why qunleashed_hn_available_bytes deliberately declines to answer for
// them.) A probe here was tried and removed for the same reason: a large malloc
// succeeds under lazy commitment, so it refused nothing and implied a check
// that was not happening.
//
// The mitigation that did work is a capacity gate in Dart before the isolate
// starts, measured against qunleashed_hn_available_bytes - see
// hardnestedMemoryVerdict in hardnested_recoverer.dart. It is a pre-flight
// refusal, not a rescue: once the engine is running, an allocation failure
// inside it is still an exit() that nothing here can catch.
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
