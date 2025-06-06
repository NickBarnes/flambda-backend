/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*          Xavier Leroy and Damien Doligez, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 2009 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/* POSIX thread implementation of the "st" interface */

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <signal.h>
#include <time.h>
#include <sys/time.h>
#ifdef __linux__
#include <features.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <limits.h>
#endif

typedef int st_retcode;

#define SIGPREEMPTION SIGVTALRM

/* OS-specific initialization */

static int st_initialize(void)
{
  caml_sigmask_hook = pthread_sigmask;
  return 0;
}

/* Thread creation.  Created in detached mode if [res] is NULL. */

typedef pthread_t st_thread_id;

static int st_thread_create(st_thread_id * res,
                            void * (*fn)(void *), void * arg)
{
  pthread_t thr;
  pthread_attr_t attr;
  int rc;

  pthread_attr_init(&attr);
  if (res == NULL) pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  rc = pthread_create(&thr, &attr, fn, arg);
  if (res != NULL) *res = thr;
  return rc;
}

#define ST_THREAD_FUNCTION void *

/* Cleanup at thread exit */

Caml_inline void st_thread_cleanup(void)
{
  return;
}

/* Thread termination */

CAMLnoreturn_start
static void st_thread_exit(void)
CAMLnoreturn_end;

static void st_thread_exit(void)
{
  pthread_exit(NULL);
}

static void st_thread_join(st_thread_id thr)
{
  pthread_join(thr, NULL);
  /* best effort: ignore errors */
}

/* Thread-specific state */

typedef pthread_key_t st_tlskey;

static int st_tls_newkey(st_tlskey * res)
{
  return pthread_key_create(res, NULL);
}

Caml_inline void * st_tls_get(st_tlskey k)
{
  return pthread_getspecific(k);
}

Caml_inline void st_tls_set(st_tlskey k, void * v)
{
  pthread_setspecific(k, v);
}

/* Windows-specific hook. */
Caml_inline void st_thread_set_id(intnat id)
{
  return;
}

/* If we're using glibc, use a custom condition variable implementation to
   avoid this bug: https://sourceware.org/bugzilla/show_bug.cgi?id=25847
   
   For now we only have this on linux because it directly uses the linux futex
   syscalls. */
#if defined(__linux__) && defined(__GNU_LIBRARY__) && defined(__GLIBC__) && defined(__GLIBC_MINOR__)
typedef struct {
  volatile unsigned counter;
} custom_condvar;

static int custom_condvar_init(custom_condvar * cv)
{
  cv->counter = 0;
  return 0;
}

static int custom_condvar_destroy(custom_condvar * cv)
{
  return 0;
}

static int custom_condvar_wait(custom_condvar * cv, pthread_mutex_t * mutex)
{
  unsigned old_count = cv->counter;
  pthread_mutex_unlock(mutex);
  syscall(SYS_futex, &cv->counter, FUTEX_WAIT_PRIVATE, old_count, NULL, NULL, 0);
  pthread_mutex_lock(mutex);
  return 0;
}

static int custom_condvar_signal(custom_condvar * cv)
{
  __sync_add_and_fetch(&cv->counter, 1);
  syscall(SYS_futex, &cv->counter, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
  return 0;
}

static int custom_condvar_broadcast(custom_condvar * cv)
{
  __sync_add_and_fetch(&cv->counter, 1);
  syscall(SYS_futex, &cv->counter, FUTEX_WAKE_PRIVATE, INT_MAX, NULL, NULL, 0);
  return 0;
}
#else
typedef pthread_cond_t custom_condvar;

static int custom_condvar_init(custom_condvar * cv)
{
  return pthread_cond_init(cv, NULL);
}

static int custom_condvar_destroy(custom_condvar * cv)
{
  return pthread_cond_destroy(cv);
}

static int custom_condvar_wait(custom_condvar * cv, pthread_mutex_t * mutex)
{
  return pthread_cond_wait(cv, mutex);
}

static int custom_condvar_signal(custom_condvar * cv)
{
  return pthread_cond_signal(cv);
}

static int custom_condvar_broadcast(custom_condvar * cv)
{
  return pthread_cond_broadcast(cv);
}
#endif

/* The master lock.  This is a mutex that is held most of the time,
   so we implement it in a slightly convoluted way to avoid
   all risks of busy-waiting.  Also, we count the number of waiting
   threads. */

typedef struct {
  pthread_mutex_t lock;         /* to protect contents  */
  int busy;                     /* 0 = free, 1 = taken */
  volatile int waiters;         /* number of threads waiting on master lock */
  custom_condvar is_free;       /* signaled when free */
} st_masterlock;

static void st_masterlock_init(st_masterlock * m)
{
  pthread_mutex_init(&m->lock, NULL);
  custom_condvar_init(&m->is_free);
  m->busy = 1;
  m->waiters = 0;
}

static void st_masterlock_acquire(st_masterlock * m)
{
  pthread_mutex_lock(&m->lock);
  while (m->busy) {
    m->waiters ++;
    custom_condvar_wait(&m->is_free, &m->lock);
    m->waiters --;
  }
  m->busy = 1;
  pthread_mutex_unlock(&m->lock);
}

static void st_masterlock_release(st_masterlock * m)
{
  pthread_mutex_lock(&m->lock);
  m->busy = 0;
  pthread_mutex_unlock(&m->lock);
  custom_condvar_signal(&m->is_free);
}

CAMLno_tsan  /* This can be called for reading [waiters] without locking. */
Caml_inline int st_masterlock_waiters(st_masterlock * m)
{
  return m->waiters;
}

/* Scheduling hints */

/* This is mostly equivalent to release(); acquire(), but better. In particular,
   release(); acquire(); leaves both us and the waiter we signal() racing to
   acquire the lock. Calling yield or sleep helps there but does not solve the
   problem. Sleeping ourselves is much more reliable--and since we're handing
   off the lock to a waiter we know exists, it's safe, as they'll certainly
   re-wake us later.
*/
Caml_inline void st_thread_yield(st_masterlock * m)
{
  pthread_mutex_lock(&m->lock);
  /* We must hold the lock to call this. */
  assert(m->busy);

  /* We already checked this without the lock, but we might have raced--if
     there's no waiter, there's nothing to do and no one to wake us if we did
     wait, so just keep going. */
  if (m->waiters == 0) {
    pthread_mutex_unlock(&m->lock);
    return;
  }

  m->busy = 0;
  custom_condvar_signal(&m->is_free);
  m->waiters++;
  do {
    /* Note: the POSIX spec prevents the above signal from pairing with this
       wait, which is good: we'll reliably continue waiting until the next
       yield() or enter_blocking_section() call (or we see a spurious condvar
       wakeup, which are rare at best.) */
       custom_condvar_wait(&m->is_free, &m->lock);
  } while (m->busy);
  m->busy = 1;
  m->waiters--;
  pthread_mutex_unlock(&m->lock);
}

/* Mutexes */

typedef pthread_mutex_t * st_mutex;

static int st_mutex_create(st_mutex * res)
{
  int rc;
  pthread_mutexattr_t attr;
  st_mutex m;

  rc = pthread_mutexattr_init(&attr);
  if (rc != 0) goto error1;
  rc = pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
  if (rc != 0) goto error2;
  m = caml_stat_alloc_noexc(sizeof(pthread_mutex_t));
  if (m == NULL) { rc = ENOMEM; goto error2; }
  rc = pthread_mutex_init(m, &attr);
  if (rc != 0) goto error3;
  pthread_mutexattr_destroy(&attr);
  *res = m;
  return 0;
error3:
  caml_stat_free(m);
error2:
  pthread_mutexattr_destroy(&attr);
error1:
  return rc;
}

static int st_mutex_destroy(st_mutex m)
{
  int rc;
  rc = pthread_mutex_destroy(m);
  caml_stat_free(m);
  return rc;
}

#define MUTEX_DEADLOCK EDEADLK

Caml_inline int st_mutex_lock(st_mutex m)
{
  return pthread_mutex_lock(m);
}

#define MUTEX_PREVIOUSLY_UNLOCKED 0
#define MUTEX_ALREADY_LOCKED EBUSY

Caml_inline int st_mutex_trylock(st_mutex m)
{
  return pthread_mutex_trylock(m);
}

#define MUTEX_NOT_OWNED EPERM

Caml_inline int st_mutex_unlock(st_mutex m)
{
  return pthread_mutex_unlock(m);
}

/* Condition variables */

typedef custom_condvar * st_condvar;

static int st_condvar_create(st_condvar * res)
{
  int rc;
  st_condvar c = caml_stat_alloc_noexc(sizeof(custom_condvar));
  if (c == NULL) return ENOMEM;
  rc = custom_condvar_init(c);
  if (rc != 0) { caml_stat_free(c); return rc; }
  *res = c;
  return 0;
}

static int st_condvar_destroy(st_condvar c)
{
  int rc;
  rc = custom_condvar_destroy(c);
  caml_stat_free(c);
  return rc;
}

Caml_inline int st_condvar_signal(st_condvar c)
{
  return custom_condvar_signal(c);
}

Caml_inline int st_condvar_broadcast(st_condvar c)
{
  return custom_condvar_broadcast(c);
}

Caml_inline int st_condvar_wait(st_condvar c, st_mutex m)
{
  return custom_condvar_wait(c, m);
}

/* Triggered events */

typedef struct st_event_struct {
  pthread_mutex_t lock;         /* to protect contents */
  int status;                   /* 0 = not triggered, 1 = triggered */
  custom_condvar triggered;     /* signaled when triggered */
} * st_event;

static int st_event_create(st_event * res)
{
  int rc;
  st_event e = caml_stat_alloc_noexc(sizeof(struct st_event_struct));
  if (e == NULL) return ENOMEM;
  rc = pthread_mutex_init(&e->lock, NULL);
  if (rc != 0) { caml_stat_free(e); return rc; }
  rc = custom_condvar_init(&e->triggered);
  if (rc != 0)
  { pthread_mutex_destroy(&e->lock); caml_stat_free(e); return rc; }
  e->status = 0;
  *res = e;
  return 0;
}

static int st_event_destroy(st_event e)
{
  int rc1, rc2;
  rc1 = pthread_mutex_destroy(&e->lock);
  rc2 = custom_condvar_destroy(&e->triggered);
  caml_stat_free(e);
  return rc1 != 0 ? rc1 : rc2;
}

static int st_event_trigger(st_event e)
{
  int rc;
  rc = pthread_mutex_lock(&e->lock);
  if (rc != 0) return rc;
  e->status = 1;
  rc = pthread_mutex_unlock(&e->lock);
  if (rc != 0) return rc;
  rc = custom_condvar_broadcast(&e->triggered);
  return rc;
}

static int st_event_wait(st_event e)
{
  int rc;
  rc = pthread_mutex_lock(&e->lock);
  if (rc != 0) return rc;
  while(e->status == 0) {
    rc = custom_condvar_wait(&e->triggered, &e->lock);
    if (rc != 0) return rc;
  }
  rc = pthread_mutex_unlock(&e->lock);
  return rc;
}

/* Reporting errors */

static void st_check_error(int retcode, char * msg)
{
  char * err;
  int errlen, msglen;
  value str;

  if (retcode == 0) return;
  if (retcode == ENOMEM) caml_raise_out_of_memory();
  err = strerror(retcode);
  msglen = strlen(msg);
  errlen = strlen(err);
  str = caml_alloc_string(msglen + 2 + errlen);
  memmove (&Byte(str, 0), msg, msglen);
  memmove (&Byte(str, msglen), ": ", 2);
  memmove (&Byte(str, msglen + 2), err, errlen);
  caml_raise_sys_error(str);
}

/* Variable used to stop the "tick" thread */
static volatile int caml_tick_thread_stop = 0;

/* The tick thread: posts a SIGPREEMPTION signal periodically */

static void * caml_thread_tick(void * arg)
{
  struct timeval timeout;
  sigset_t mask;

  /* Block all signals so that we don't try to execute an OCaml signal handler*/
  sigfillset(&mask);
  pthread_sigmask(SIG_BLOCK, &mask, NULL);
  while(! caml_tick_thread_stop) {
    /* select() seems to be the most efficient way to suspend the
       thread for sub-second intervals */
    timeout.tv_sec = 0;
    timeout.tv_usec = Thread_timeout * 1000;
    select(0, NULL, NULL, NULL, &timeout);
    /* The preemption signal should never cause a callback, so don't
     go through caml_handle_signal(), just record signal delivery via
     caml_record_signal(). */
    caml_record_signal(SIGPREEMPTION);
  }
  return NULL;
}

/* "At fork" processing */

#if defined(__ANDROID__)
/* Android's libc does not include declaration of pthread_atfork;
   however, it implements it since API level 10 (Gingerbread).
   The reason for the omission is that Android (GUI) applications
   are not supposed to fork at all, however this workaround is still
   included in case OCaml is used for an Android CLI utility. */
int pthread_atfork(void (*prepare)(void), void (*parent)(void),
                   void (*child)(void));
#endif

static int st_atfork(void (*fn)(void))
{
  return pthread_atfork(NULL, NULL, fn);
}

/* Signal handling */

static void st_decode_sigset(value vset, sigset_t * set)
{
  sigemptyset(set);
  while (vset != Val_int(0)) {
    int sig = caml_convert_signal_number(Int_val(Field(vset, 0)));
    sigaddset(set, sig);
    vset = Field(vset, 1);
  }
}

#ifndef NSIG
#define NSIG 64
#endif

static value st_encode_sigset(sigset_t * set)
{
  value res = Val_int(0);
  int i;

  Begin_root(res)
    for (i = 1; i < NSIG; i++)
      if (sigismember(set, i) > 0) {
        value newcons = caml_alloc_small(2, 0);
        Field(newcons, 0) = Val_int(caml_rev_convert_signal_number(i));
        Field(newcons, 1) = res;
        res = newcons;
      }
  End_roots();
  return res;
}

static int sigmask_cmd[3] = { SIG_SETMASK, SIG_BLOCK, SIG_UNBLOCK };

value caml_thread_sigmask(value cmd, value sigs) /* ML */
{
  int how;
  sigset_t set, oldset;
  int retcode;

  how = sigmask_cmd[Int_val(cmd)];
  st_decode_sigset(sigs, &set);
  caml_enter_blocking_section();
  retcode = pthread_sigmask(how, &set, &oldset);
  caml_leave_blocking_section();
  st_check_error(retcode, "Thread.sigmask");
  /* Run any handlers for just-unmasked pending signals */
  caml_process_pending_actions();
  return st_encode_sigset(&oldset);
}

value caml_wait_signal(value sigs) /* ML */
{
  sigset_t set;
  int retcode, signo;

  st_decode_sigset(sigs, &set);
  caml_enter_blocking_section();
  retcode = sigwait(&set, &signo);
  caml_leave_blocking_section();
  st_check_error(retcode, "Thread.wait_signal");
  return Val_int(caml_rev_convert_signal_number(signo));
}
