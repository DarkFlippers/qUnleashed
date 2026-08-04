// Compat shim so PM3's hardnested core compiles outside the PM3 client:
// stubs the ui/comms/fileutils/util_posix symbols the offline solver references.
#ifndef HN_COMPAT_H
#define HN_COMPAT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

// ---- ui.h ----
#define PrintAndLogEx(...) \
  do {                     \
  } while (0)
#define _YELLOW_(s) s
#define _GREEN_(s) s
#define _RED_(s) s
#define _CYAN_(s) s
#ifndef NORMAL
#define NORMAL 0
#define INFO 0
#define ERR 0
#define SUCCESS 0
#define FAILED 0
#endif

// ---- commonutil.h ----
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef ARRAYLEN
#define ARRAYLEN(x) (sizeof(x) / sizeof((x)[0]))
#endif

// ---- pm3_cmd.h ----
#ifndef PM3_SUCCESS
#define PM3_SUCCESS 0
#endif
// RESOURCES_SUBDIR comes from crapto1/common.h (via parity.h)

// ---- util_posix.h ----
static inline uint64_t msclock(void) {
  return (uint64_t)(clock() * 1000ULL / CLOCKS_PER_SEC);
}

// number of worker threads
static inline int num_CPUs(void) { return 4; }

// ---- fileutils.h : locate a resource file ----
// For the standalone bench this points at PM3's shipped resources dir.
static inline int searchFile(
    char **foundpath,
    const char *pm3dir,
    const char *searchname,
    const char *suffix,
    int silent) {
  (void)pm3dir;
  (void)suffix;
  (void)silent;
  const char *base =
      "C:/Projects/ProxSpace/pm3/proxmark3/client/resources/";
  size_t n = strlen(base) + strlen(searchname) + 1;
  char *p = (char *)malloc(n);
  if (p == NULL) return -1;
  snprintf(p, n, "%s%s", base, searchname);
  *foundpath = p;
  return PM3_SUCCESS;
}

// ---- cmdhfmfhard.h : progress callbacks (no-op here) ----
static inline void hardnested_print_progress(
    uint32_t nonces,
    const char *activity,
    float brute_force,
    uint64_t min_diff_print_time) {
  (void)nonces;
  (void)activity;
  (void)brute_force;
  (void)min_diff_print_time;
}
static inline void hardnested_print_key_found_progress(
    uint32_t num_acquired_nonces,
    const char *keystr) {
  (void)num_acquired_nonces;
  (void)keystr;
}

#endif
