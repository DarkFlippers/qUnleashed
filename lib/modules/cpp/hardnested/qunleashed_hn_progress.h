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
  // Set by the caller to ask the attack to stop. Checked in three places: every
  // block inside the brute force, so a stop costs one block rather than the
  // bucket in hand; the bucket loop around it; and the Sum(a8) guess loop that
  // drives both, which would otherwise walk every remaining guess because an
  // aborted brute force reports no key. A stop is therefore bounded but not
  // immediate - the phases before the brute force (table decompression, nonce
  // ingestion, candidate generation) do not consult it, and a Stop during one of
  // those waits it out.
  //
  // The finest check used to be the bucket boundary, which on the scalar Windows
  // build meant tens of minutes: the button greyed out and the attack carried
  // on. The phases outside the brute force are unchanged - a Stop during
  // candidate generation still waits for it.
  volatile uint32_t abort;
  // Set the first time a percentage is published, so the caller can tell "no
  // progress yet" from "zero percent". qunleashed_hn_set_total publishes a zero
  // before the workers start, so in practice it is set for the whole of a
  // brute force and clear for the phases before it.
  volatile uint32_t started;
} qunleashed_hn_progress;

// Installs the channel for the attack. NULL detaches, which is what a caller
// that wants neither progress nor cancellation passes.
//
// One attack at a time: the bridge refuses a second channel-bearing attack with
// -4 rather than letting it take the first one's channel, and the Dart side also
// walks sector keys in series.
void qunleashed_hn_set_progress(qunleashed_hn_progress *channel);

// Whether a channel is already installed, so the bridge can refuse a second
// attack rather than let it take the first one's.
int qunleashed_hn_progress_busy(void);

// Engine-side helpers. Safe to call with no channel installed.
void qunleashed_hn_report_permille(uint32_t permille);
int qunleashed_hn_aborted(void);

// Declares how many states the brute force about to start will test, and
// resets the count. Called once per Sum(a8) guess, since each guess searches a
// candidate set of its own - which is why the bar restarts rather than
// continuing: it is a new search, and pretending otherwise would be a
// percentage of nothing in particular.
void qunleashed_hn_set_total(uint64_t total_states);

// Adds to the tested count and republishes the percentage, when there is a
// total to divide by - a guess that declared none reports nothing rather than a
// figure of its own invention.
//
// Called from every brute-force worker thread, many times per bucket. That is
// the point: the engine used to report once per *completed* bucket, and a
// bucket on a slow build runs for tens of minutes, so the first report of an
// attack arrived long after the user had decided it was hung. The counter it
// divided by was advanced at the same bucket boundary, so there was nothing
// finer to report even if it had asked.
void qunleashed_hn_add_tested(uint64_t states);

#endif  // QUNLEASHED_HN_PROGRESS_H
