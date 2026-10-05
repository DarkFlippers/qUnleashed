#include "qunleashed_hn_progress.h"

#include <stddef.h>

// One attack at a time per process, which is what the caller does: the recovery
// run walks sector keys in series, and the engine's own state is global anyway
// (bitflip tables, bucket lists, the found-key counter). A second concurrent
// attack would collide long before it collided here.
static qunleashed_hn_progress *volatile g_channel = NULL;

void qunleashed_hn_set_progress(qunleashed_hn_progress *channel) {
  g_channel = channel;
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
