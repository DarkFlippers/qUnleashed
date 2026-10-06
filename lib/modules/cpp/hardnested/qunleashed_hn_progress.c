#include "qunleashed_hn_progress.h"

#include <stddef.h>

// The tested/total counters are written by every brute-force worker thread at
// once, so unlike the channel's fields they need a real atomic add rather than
// volatile. One intrinsic each way; C11 atomics are not dependable under MSVC,
// which is the reason the rest of this file avoids them too.
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
  channel->permille = permille > 1000 ? 1000 : permille;
  channel->started = 1;
}

int qunleashed_hn_aborted(void) {
  qunleashed_hn_progress *const channel = g_channel;
  return channel != NULL && channel->abort != 0;
}

void qunleashed_hn_set_total(uint64_t total_states) {
  g_tested_states = 0;
  g_total_states = total_states;
}

void qunleashed_hn_add_tested(uint64_t states) {
  const uint64_t total = g_total_states;
  const uint64_t tested = hn_atomic_add64(&g_tested_states, states);
  if (total == 0) {
    return;
  }
  // No overflow to guard: a candidate set that could make tested * 1000 wrap
  // 64 bits would be some 2^54 times larger than the largest the engine builds.
  const uint64_t permille = (tested * 1000u) / total;
  qunleashed_hn_report_permille(
      (uint32_t)(permille > 1000 ? 1000 : permille));
}
