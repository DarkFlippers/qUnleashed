// The FFI entry points Dart resolves by name for SubGHz seed recovery.
//
// Thin on purpose: the search is the engine's, the variant choice is the
// dispatcher's, and everything here is either a name Dart can find or a figure
// Dart cannot get for itself. Keeping every export in one readable file is also
// what lets `.github/scripts/check_ffi_exports.sh` read the expected names off
// the definitions rather than restating them.
#include "faaccrack.h"

#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

// `used` as well as default visibility, and the reason is not theoretical: on
// Apple the MIFARE bridges shipped stripped because ld64 roots an executable's
// dead-stripping at its entry point, not at its exported globals, and nothing
// in Swift or Obj-C calls these - only Dart does, by name, at runtime. That
// cost every MIFARE recovery path on both Apple platforms. The note on
// QUNLEASHED_EXPORT in ../mfkey32/nested_bridge.c is the canonical account.
#if defined(_WIN32)
#define QUNLEASHED_EXPORT __declspec(dllexport)
#else
#define QUNLEASHED_EXPORT __attribute__((visibility("default"), used))
#endif

// Recovers the seed for one capture.
//
// A straight pass-through to the dispatcher, which is the point: the argument
// checking, the busy gate and the status vocabulary are all the engine's and
// the dispatcher's, and a bridge that re-stated any of them would be a second
// place for them to drift. See faaccrack.h for what each status means and what
// a caller may do with the result.
//
// The caller allocates and zeroes both structs and keeps them alive across the
// call; `progress` may be null, in which case the search cannot be stopped.
QUNLEASHED_EXPORT int qunleashed_faaccrack_recover(uint32_t mode, uint32_t fix,
                                                   const uint32_t *hops, uint32_t nhop,
                                                   int threads,
                                                   struct faaccrack_progress *progress,
                                                   struct faaccrack_result *result) {
  return faaccrack_search(mode, fix, hops, nhop, threads, progress, result);
}

// How many hardware threads this machine has, or 0 for "no answer".
//
// An export rather than something Dart works out, for two reasons. The ABI
// requires the caller to pass a thread count, so the figure has to come from
// somewhere; and Dart's own `Platform.numberOfProcessors` reports what the VM
// sees, which on Android is not reliably the count an app may actually use.
// 0 must be read as "pick a default", never as "no CPUs".
QUNLEASHED_EXPORT uint32_t qunleashed_faaccrack_cpu_count(void) {
#if defined(_WIN32)
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  return (uint32_t)info.dwNumberOfProcessors;
#elif defined(_SC_NPROCESSORS_ONLN)
  const long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 ? (uint32_t)count : 0u;
#else
  return 0u;
#endif
}

// The size of the result struct, so the Dart mirror can assert it matches.
//
// This closes the one hole the build cannot: `keep.txt` and the compiler
// between them keep the C side honest, and `_Static_assert`s in faaccrack.h pin
// the layout for every variant - but nothing protects a hand-written Dart
// `Struct`. Add a field and Dart reads wrong offsets with no compile error, no
// link error, and a plausible-looking seed.
QUNLEASHED_EXPORT uint32_t qunleashed_faaccrack_result_size(void) {
  return (uint32_t)sizeof(struct faaccrack_result);
}

// The same for the progress channel, which Dart also mirrors by hand.
QUNLEASHED_EXPORT uint32_t qunleashed_faaccrack_progress_size(void) {
  return (uint32_t)sizeof(struct faaccrack_progress);
}

// Which per-instruction-set variant the dispatcher picked, as a static string.
//
// Diagnostic, and the only answer to "why is this machine several times slower
// than that one". The pointer is to a literal with static storage duration, so
// Dart may hold it for the life of the process.
QUNLEASHED_EXPORT const char *qunleashed_faaccrack_variant(void) {
  return faaccrack_variant_name();
}
