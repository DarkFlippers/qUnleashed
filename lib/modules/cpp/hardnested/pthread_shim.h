//-----------------------------------------------------------------------------
// Minimal pthreads shim over Win32, for toolchains that ship no <pthread.h>
// (clang-cl / MSVC). MinGW has winpthreads; Linux/Android/macOS/iOS have real
// pthreads; so this is used only on Windows-non-MinGW. Covers exactly the
// surface the hardnested engine uses: pthread_create/join and non-recursive
// pthread_mutex_* (SRWLOCK-backed, which has a static initializer).
//-----------------------------------------------------------------------------
#ifndef QUNLEASHED_PTHREAD_SHIM_H
#define QUNLEASHED_PTHREAD_SHIM_H

#include <windows.h>
#include <process.h>
#include <stdint.h>
#include <stdlib.h>

typedef HANDLE pthread_t;
typedef SRWLOCK pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT

typedef struct {
  void *(*start_routine)(void *);
  void *arg;
} qu_pthread_trampoline_t;

static unsigned __stdcall qu_pthread_entry(void *raw) {
  qu_pthread_trampoline_t *t = (qu_pthread_trampoline_t *)raw;
  void *(*fn)(void *) = t->start_routine;
  void *arg = t->arg;
  free(t);
  fn(arg);
  return 0;
}

static inline int pthread_create(pthread_t *thread, const void *attr,
                                 void *(*start_routine)(void *), void *arg) {
  (void)attr;
  qu_pthread_trampoline_t *t = (qu_pthread_trampoline_t *)malloc(sizeof(*t));
  if (t == NULL) return -1;
  t->start_routine = start_routine;
  t->arg = arg;
  uintptr_t h = _beginthreadex(NULL, 0, qu_pthread_entry, t, 0, NULL);
  if (h == 0) {
    free(t);
    return -1;
  }
  *thread = (HANDLE)h;
  return 0;
}

static inline int pthread_join(pthread_t thread, void **retval) {
  (void)retval;
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
  return 0;
}

static inline int pthread_mutex_init(pthread_mutex_t *m, const void *attr) {
  (void)attr;
  InitializeSRWLock(m);
  return 0;
}
static inline int pthread_mutex_lock(pthread_mutex_t *m) {
  AcquireSRWLockExclusive(m);
  return 0;
}
static inline int pthread_mutex_unlock(pthread_mutex_t *m) {
  ReleaseSRWLockExclusive(m);
  return 0;
}
static inline int pthread_mutex_destroy(pthread_mutex_t *m) {
  (void)m;
  return 0;
}

#endif // QUNLEASHED_PTHREAD_SHIM_H
