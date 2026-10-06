#include "qunleashed_hn_progress.h"

#include <stddef.h>

// g_tested_states is incremented by every brute-force worker at once, so it
// needs a real atomic add rather than volatile. g_total_states is set once
// before the workers are created and only read after, so a plain volatile store
// is enough for it. One intrinsic each way; C11 atomics are not dependable
// under MSVC, which is why the rest of this file avoids them too.
#ifdef _MSC_VER
#include <Windows.h>
#define hn_atomic_add64(p, v) \
  ((uint64_t)InterlockedExchangeAdd64((volatile LONG64 *)(p), (LONG64)(v)) + (v))
#else
#define hn_atomic_add64(p, v) __sync_add_and_fetch((p), (v))
#endif

// One attack at a time per process, which is what the caller does: the recovery
// run walks sector keys in series, and the engine's own state is global anyway
// (bitflip tables, bucket lists, the found-key counter). A second concurrent
// attack would collide long before it collided here.
static qunleashed_hn_progress *volatile g_channel = NULL;

// How many states this guess will test, and how many have been. Separate from
// the engine's own `num_keys_tested`, which is advanced only when a whole
// bucket is finished and is used for its own rate arithmetic.
static volatile uint64_t g_total_states = 0;
static volatile uint64_t g_tested_states = 0;

void qunleashed_hn_set_progress(qunleashed_hn_progress *channel) {
  g_channel = channel;
  // Cleared with the channel, so a second attack in the same process cannot
  // inherit the first one's denominator and report a percentage of it.
  g_total_states = 0;
  g_tested_states = 0;
}

int qunleashed_hn_progress_busy(void) { return g_channel != NULL; }

void qunleashed_hn_report_permille(uint32_t permille) {
  qunleashed_hn_progress *const channel = g_channel;
  if (channel == NULL) {
    return;
  }
  const uint32_t clamped = permille > 1000 ? 1000 : permille;
  // Written only when it changes, which is what makes the per-block abort check
  // cheap. The three fields share a cache line, so storing `started` on every
  // call dirtied that line from every worker and turned the `abort` read in the
  // brute force into a guaranteed cross-core miss. Measured: the reporting pair
  // cost ~50 ns a call that way against ~8 ns for the atomic alone, and the
  // abort read drops to ~0.2 ns once the line stays Shared between steps.
  // There are at most 1001 distinct values per guess, so this skips almost
  // every store.
  if (channel->permille != clamped || channel->started == 0) {
    channel->permille = clamped;
    channel->started = 1;
  }
}

int qunleashed_hn_aborted(void) {
  qunleashed_hn_progress *const channel = g_channel;
  return channel != NULL && channel->abort != 0;
}

void qunleashed_hn_set_total(uint64_t total_states) {
  g_tested_states = 0;
  g_total_states = total_states;
  // Published, not just stored. Two reasons: the bar must visibly restart
  // rather than inherit the previous guess's figure, and this is now the only
  // thing that sets `started` - the per-bucket report this replaced used to set
  // it unconditionally, so without this a guess with no declared total would
  // run to completion with the UI still showing "no progress yet".
  qunleashed_hn_report_permille(0);
}

void qunleashed_hn_add_tested(uint64_t states) {
  const uint64_t total = g_total_states;
  const uint64_t tested = hn_atomic_add64(&g_tested_states, states);
  if (total == 0) {
    return;
  }
  // No clamp here: report_permille does it, and doing it twice only invites the
  // two to disagree. No overflow to guard either - a candidate set that could
  // make tested * 1000 wrap 64 bits would be some 2^54 times larger than the
  // largest the engine builds.
  qunleashed_hn_report_permille((uint32_t)((tested * 1000u) / total));
}
