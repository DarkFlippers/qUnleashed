//-----------------------------------------------------------------------------
// Minimal pthreads shim over Win32, for toolchains that ship no <pthread.h>
// (clang-cl / MSVC). MinGW has winpthreads, Linux/Android/macOS/iOS have real
// pthreads, so this is used only on Windows-non-MinGW (see hn_compat.h).
//
// Covers exactly the surface the hardnested code uses: pthread_create/join and
// non-recursive pthread_mutex_*. Threads always pass a NULL attr and ignore the
// join return value; mutexes are backed by SRWLOCK because it (unlike
// CRITICAL_SECTION) has a static initializer, which the code relies on via
// PTHREAD_MUTEX_INITIALIZER.
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
  void *(*start_routine)(void *) = t->start_routine;
  void *arg = t->arg;
  free(t);
  start_routine(arg);
  return 0;
}

static inline int pthread_create(pthread_t *thread, const void *attr,
                                 void *(*start_routine)(void *), void *arg) {
  (void)attr; // always NULL in this codebase
  qu_pthread_trampoline_t *t =
      (qu_pthread_trampoline_t *)malloc(sizeof(*t));
  if (t == NULL) return -1;
  t->start_routine = start_routine;
  t->arg = arg;
  uintptr_t handle = _beginthreadex(NULL, 0, qu_pthread_entry, t, 0, NULL);
  if (handle == 0) {
    free(t);
    return -1;
  }
  *thread = (HANDLE)handle;
  return 0;
}

static inline int pthread_join(pthread_t thread, void **retval) {
  (void)retval; // return value never used by the callers
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
  return 0;
}

static inline int pthread_mutex_init(pthread_mutex_t *mutex, const void *attr) {
  (void)attr;
  InitializeSRWLock(mutex);
  return 0;
}

static inline int pthread_mutex_lock(pthread_mutex_t *mutex) {
  AcquireSRWLockExclusive(mutex);
  return 0;
}

static inline int pthread_mutex_unlock(pthread_mutex_t *mutex) {
  ReleaseSRWLockExclusive(mutex);
  return 0;
}

static inline int pthread_mutex_destroy(pthread_mutex_t *mutex) {
  (void)mutex; // SRWLOCK needs no teardown
  return 0;
}

#endif // QUNLEASHED_PTHREAD_SHIM_H
