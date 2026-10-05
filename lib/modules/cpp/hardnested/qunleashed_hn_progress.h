#ifndef QUNLEASHED_HN_PROGRESS_H
#define QUNLEASHED_HN_PROGRESS_H

#include <stdint.h>

// A window into a running hardnested attack, and the way to stop one.
//
// The attack is the longest thing this app does - minutes to hours for a single
// sector key - and until now it reported nothing and could not be interrupted:
// the brute-force percentage was already computed inside the engine and sent to
// `printf`, which on a phone is nowhere, and Stop was checked only between
// sector keys.
//
// No time estimate. The engine measures its own rate only in `brute_force_bs`,
// after `pthread_join` - that is, once the attack it would have described has
// already finished - so a live estimate is not available to report. The figure
// it prints before then is a placeholder workload divided by a rate of zero.
//
// Shared memory rather than a callback. The engine reports from its brute-force
// worker threads, and a Dart FFI callback has to be marshalled back to the
// isolate that owns it; polling a few aligned words costs nothing, cannot
// deadlock, and does not care which thread wrote them. The caller allocates
// this, hands over the pointer, and reads it on a timer while the attack runs
// in another isolate - the memory is process-scoped, so both see it.
//
// Each field is a naturally aligned 32-bit word written by one side and read by
// the other. `volatile` rather than `_Atomic` because this builds under MSVC
// too, where C11 atomics are not dependable - and because what is needed here
// is not an ordering guarantee but the promise that the compiler re-reads the
// word instead of hoisting it. That matters for `abort` specifically: the
// Apple build compiles this file and the brute-force loop into one translation
// unit, so without it the check could be lifted out of the loop and Stop would
// never reach a running attack.
//
// Staleness is otherwise harmless: a late `permille` costs one frame of a bar,
// and nothing orders the fields against each other.
typedef struct {
  // Completion of the brute-force phase in tenths of a percent, 0..1000. The
  // phases before it do not report one: they are bounded and comparatively
  // short, and inventing a number for them would be worse than an honest
  // "working".
  volatile uint32_t permille;
  // Set by the caller to ask the attack to stop. Checked in the brute-force
  // worker loop, where the engine already checks whether another thread found
  // the key, so a stop there costs at most one bucket. The phases before it -
  // table decompression, nonce ingestion, candidate generation - do not consult
  // it, and a Stop during those waits them out.
  volatile uint32_t abort;
  // Set by the engine once the brute force is live, so the caller can tell "no
  // progress yet" from "zero percent".
  volatile uint32_t started;
} qunleashed_hn_progress;

// Installs the channel for the attack. One attack at a time per process. NULL detaches,
// which is what every non-Dart caller (the tests, the CLI) gets.
//
// One attack at a time is the *caller's* invariant, not this file's: a second
// concurrent recover would clobber the first's channel and its abort writes
// would go nowhere. The Dart side holds it by walking sector keys in series.
void qunleashed_hn_set_progress(qunleashed_hn_progress *channel);

// Engine-side helpers. Safe to call with no channel installed.
// Whether a channel is already installed, so a second attack can be refused
// rather than silently taking the first one's.
int qunleashed_hn_progress_busy(void);

void qunleashed_hn_report_permille(uint32_t permille);
int qunleashed_hn_aborted(void);

#endif  // QUNLEASHED_HN_PROGRESS_H
