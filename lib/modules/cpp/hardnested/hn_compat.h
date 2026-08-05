// Compat shim so PM3's hardnested core compiles outside the PM3 client:
// stubs the ui/comms/fileutils/util_posix symbols the offline solver references.
#ifndef HN_COMPAT_H
#define HN_COMPAT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <pthread.h>

// ---- ui.h ----
#define PrintAndLogEx(...) \
  do {                     \
  } while (0)
#define _YELLOW_(s) s
#define _GREEN_(s) s
#define _RED_(s) s
#define _CYAN_(s) s
// log-level tokens (WARNING/INFO/...) are swallowed by the no-op PrintAndLogEx
// above, so they need no definitions.

// ---- commonutil.h ----
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef ARRAYLEN
#define ARRAYLEN(x) (sizeof(x) / sizeof((x)[0]))
#endif
// big-endian bytes -> integer (crapto1 keys/uids)
static inline uint64_t bytes_to_num(const uint8_t *src, size_t len) {
  uint64_t num = 0;
  while (len--) {
    num = (num << 8) | (*src);
    src++;
  }
  return num;
}

// ---- pm3_cmd.h : return codes (values match proxmark3's pm3_cmd.h) ----
#ifndef PM3_SUCCESS
#define PM3_SUCCESS 0
#define PM3_EINVARG (-2)
#define PM3_ETIMEOUT (-4)
#define PM3_ESOFT (-10)
#define PM3_EMALLOC (-12)
#define PM3_EFILE (-13)
#define PM3_EFAILED (-19)
#endif
// RESOURCES_SUBDIR comes from crapto1/common.h (via parity.h)

// ---- util_posix.h ----
static inline uint64_t msclock(void) {
  return (uint64_t)(clock() * 1000ULL / CLOCKS_PER_SEC);
}

// number of worker threads
static inline int num_CPUs(void) { return 4; }

// ---- util_posix.h : executable dir (only used to size a path buffer) ----
static inline const char *get_my_executable_directory(void) { return ""; }

// Root directory that holds the hardnested_tables/ folder. The host app sets
// this (via qunleashed_hardnested_set_tables_path) to wherever it extracted the
// bundled bitflip tables; empty until then. Defined in cmdhfmfhard.c.
extern char g_hardnested_tables_path[1024];

// ---- fileutils.h : locate a resource file under g_hardnested_tables_path ----
// Checks existence (unlike an always-succeed stub) so init_bitflip_bitarrays'
// raw->lz4->bz2 fallback selects the format actually present.
static inline int searchFile(
    char **foundpath,
    const char *pm3dir,
    const char *searchname,
    const char *suffix,
    int silent) {
  (void)pm3dir;
  (void)suffix;
  (void)silent;
  size_t bl = strlen(g_hardnested_tables_path);
  if (bl == 0) return PM3_EFILE;
  int need_sep = (g_hardnested_tables_path[bl - 1] != '/' &&
                  g_hardnested_tables_path[bl - 1] != '\\');
  size_t n = bl + (need_sep ? 1 : 0) + strlen(searchname) + 1;
  char *p = (char *)malloc(n);
  if (p == NULL) return PM3_EMALLOC;
  snprintf(p, n, "%s%s%s", g_hardnested_tables_path, need_sep ? "/" : "",
           searchname);
  FILE *fh = fopen(p, "rb");
  if (fh == NULL) {
    free(p);
    return PM3_EFILE;
  }
  fclose(fh);
  *foundpath = p;
  return PM3_SUCCESS;
}

// ---- cmdhfmfhard.h : progress callbacks (real defs live in cmdhfmfhard.c;
// the bruteforce driver only needs the declarations) ----
void hardnested_print_progress(
    uint32_t nonces,
    const char *activity,
    float brute_force,
    uint64_t min_diff_print_time);
void hardnested_print_key_found_progress(
    uint32_t num_acquired_nonces,
    const char *keystr);

#endif
