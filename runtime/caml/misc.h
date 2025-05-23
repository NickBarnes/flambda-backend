/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*          Xavier Leroy and Damien Doligez, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 1996 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/* Miscellaneous macros and variables. */

#ifndef CAML_MISC_H
#define CAML_MISC_H

#include "config.h"

/* Standard definitions */

#include <stddef.h>
#include <stdlib.h>
#include <stdarg.h>
#include <limits.h>

#include "camlatomic.h"

/* Deprecation warnings */

#if defined(__GNUC__) || defined(__clang__)
  /* Supported since at least GCC 3.1 */
  #define CAMLdeprecated_typedef(name, type) \
    typedef type name __attribute ((deprecated))
#elif defined(_MSC_VER)
  #define CAMLdeprecated_typedef(name, type) \
    typedef __declspec(deprecated) type name
#else
  #define CAMLdeprecated_typedef(name, type) typedef type name
#endif

#if defined(__GNUC__)                                           \
    && defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L \
    || defined(_MSC_VER) && _MSC_VER >= 1925

#define CAML_STRINGIFY(x) #x
#ifdef _MSC_VER
#define CAML_MAKEWARNING1(x) CAML_STRINGIFY(message(x))
#else
#define CAML_MAKEWARNING1(x) CAML_STRINGIFY(GCC warning x)
#endif
#define CAML_MAKEWARNING2(y) CAML_MAKEWARNING1(#y)
#define CAML_PREPROWARNING(x) _Pragma(CAML_MAKEWARNING2(x))
#define CAML_DEPRECATED(name1,name2) \
  CAML_PREPROWARNING(name1 is deprecated: use name2 instead)

#else

#define CAML_PREPROWARNING(msg)
#define CAML_DEPRECATED(name1,name2)

#endif

/* Basic types and constants */

typedef size_t asize_t;

#ifndef NULL
#define NULL 0
#endif

#ifdef CAML_INTERNALS
CAMLdeprecated_typedef(addr, char *);
#endif /* CAML_INTERNALS */

/* Noreturn, CAMLnoreturn_start and CAMLnoreturn_end are preserved
   for compatibility reasons.  Instead, we recommend using the CAMLnoret
   macro, to be added as a modifier at the beginning of the
   function definition or declaration.  It must occur first, before
   "static", "extern", "CAMLexport", "CAMLextern".

   Note: CAMLnoreturn is a different macro defined in memory.h,
   to be used in function bodies rather than as a function attribute.
*/
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202300L    \
    || defined(__cplusplus) && __cplusplus >= 201103L
  #define CAMLnoret [[noreturn]]
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
  #define CAMLnoret _Noreturn
#elif defined(__GNUC__)
  #define CAMLnoret  __attribute__ ((noreturn))
#else
  #define CAMLnoret
#endif

#define CAMLnoreturn_start CAMLnoret
#define CAMLnoreturn_end

#ifdef __GNUC__
  #define Noreturn __attribute__ ((noreturn))
#else
  #define Noreturn
#endif

/* Manually preventing inlining */
#if defined(__GNUC__)
  #define Caml_noinline __attribute__ ((noinline))
#elif defined(_MSC_VER)
  #define Caml_noinline __declspec(noinline)
#else
  #define Caml_noinline
#endif

/* Export control (to mark primitives and to handle Windows DLL) */

#ifndef CAMLDLLIMPORT
  #if defined(SUPPORT_DYNAMIC_LINKING) && defined(ARCH_SIXTYFOUR) \
      && (defined(__CYGWIN__) || defined(__MINGW32__))
    #define CAMLDLLIMPORT __declspec(dllimport)
  #else
    #define CAMLDLLIMPORT
  #endif
#endif

#define CAMLexport
#ifndef CAML_NO_DEFINE_CAMLprim
#define CAMLprim
#endif
#define CAMLextern CAMLDLLIMPORT extern

/* Weak function definitions that can be overridden by external libs */
/* Conservatively restricted to ELF and MacOSX platforms */
#if defined(__GNUC__) && (defined (__ELF__) || defined(__APPLE__))
#define CAMLweakdef __attribute__((weak))
#else
#define CAMLweakdef
#endif

/* Alignment is necessary for domain_state.h, since the code generated */
/* by ocamlopt makes direct references into the domain state structure,*/
/* which is stored in a register on many platforms. For this to work, */
/* we need to be able to compute the exact offset of each member. */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define CAMLalign(n) _Alignas(n)
#elif defined(__cplusplus) \
   && (__cplusplus >= 201103L || defined(_MSC_VER) && _MSC_VER >= 1900)
#define CAMLalign(n) alignas(n)
#elif defined(SUPPORTS_ALIGNED_ATTRIBUTE)
#define CAMLalign(n) __attribute__((aligned(n)))
#elif defined(_MSC_VER)
#define CAMLalign(n) __declspec(align(n))
#else
#error "How do I align values on this platform?"
#endif

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L || \
    defined(__cplusplus)
#define CAMLthread_local thread_local
#else
#define CAMLthread_local _Thread_local
#endif

/* Prefetching */

#ifdef CAML_INTERNALS
#if defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
#define caml_prefetch(p) __builtin_prefetch((p), 1, 3)
/* 1 = intent to write; 3 = all cache levels */
#else
#define caml_prefetch(p)
#endif
#endif /* CAML_INTERNALS */

/* CAMLunused is preserved for compatibility reasons.
   Instead of the legacy GCC/Clang-only
     CAMLunused foo;
   you should prefer
     CAMLunused_start foo CAMLunused_end;
   which supports both GCC/Clang and MSVC.
*/
#if defined(__GNUC__) && (__GNUC__ > 2 || (__GNUC__ == 2 && __GNUC_MINOR__ > 7))
  #define CAMLunused_start __attribute__ ((unused))
  #define CAMLunused_end
  #define CAMLunused __attribute__ ((unused))
#elif defined(_MSC_VER)
  #define CAMLunused_start  __pragma( warning (push) )           \
    __pragma( warning (disable:4189 ) )
  #define CAMLunused_end __pragma( warning (pop))
  #define CAMLunused
#else
  #define CAMLunused_start
  #define CAMLunused_end
  #define CAMLunused
#endif

/* GC timing hooks. These can be assigned by the user. These hooks
   must not allocate, change any heap value, nor call OCaml code. They
   can obtain the domain id with Caml_state->id. These functions must
   be reentrant. */
#ifndef __cplusplus
typedef void (*caml_timing_hook) (void);
extern _Atomic caml_timing_hook caml_major_slice_begin_hook;
extern _Atomic caml_timing_hook caml_major_slice_end_hook;
extern _Atomic caml_timing_hook caml_minor_gc_begin_hook;
extern _Atomic caml_timing_hook caml_minor_gc_end_hook;
extern _Atomic caml_timing_hook caml_finalise_begin_hook;
extern _Atomic caml_timing_hook caml_finalise_end_hook;
extern _Atomic caml_timing_hook caml_domain_terminated_hook;
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifdef CAML_INTERNALS

#ifndef __cplusplus
Caml_inline void call_timing_hook(_Atomic caml_timing_hook * a)
{
  caml_timing_hook h = atomic_load_explicit(a, memory_order_relaxed);
  if (h != NULL) (*h)();
}
#endif

#endif /* CAML_INTERNALS */

/* Windows Unicode support (rest below - char_os is needed earlier) */

#ifdef _WIN32
typedef wchar_t char_os;
#else
typedef char char_os;
#endif

/* Assertions */

#ifdef DEBUG

#ifdef UNICODE
/* See https://msdn.microsoft.com/ja-jp/library/b0084kay(v=vs.71).aspx
   It's not clear why this isn't so obviously documented, as it doesn't
   seem to have been superseded by a more sensible mechanism! */
#define CAML_WIDEN_STRING_LITERAL2(x) L##x
#define CAML_WIDEN_STRING_LITERAL(x) CAML_WIDEN_STRING_LITERAL2(x)
#define __OSFILE__ CAML_WIDEN_STRING_LITERAL(__FILE__)
#else
#define __OSFILE__ __FILE__
#endif

/* Although caml_failed_assert never returns, it is not marked as such.
   This prevents the C compiler optimising away all of the useful context
   from the callsite, making debuggers able to see it. */
#define CAMLassert(x) \
  (CAMLlikely(x) ? (void) 0 : caml_failed_assert ( #x , __OSFILE__, __LINE__))
CAMLextern void caml_failed_assert (char *, char_os *, int)
#if defined(__has_feature)
  /* However, we do inform clang-analyzer that this function never returns,
     since that improves analysis without breaking debugging */
  #if __has_feature(attribute_analyzer_noreturn)
    __attribute__((analyzer_noreturn))
  #endif
#endif
;
#else
#define CAMLassert(x) ((void) 0)
#endif

#ifdef __GNUC__
#define CAMLlikely(e)   __builtin_expect(!!(e), 1)
#define CAMLunlikely(e) __builtin_expect(!!(e), 0)
#else
#define CAMLlikely(e) (e)
#define CAMLunlikely(e) (e)
#endif

#ifdef CAML_INTERNALS

/* GC status assertions.

   CAMLnoalloc at the start of a block means that the GC must not be
   invoked during the block. */
#if defined(__GNUC__) && defined(DEBUG)
int caml_noalloc_begin(void);
void caml_noalloc_end(int*);
void caml_alloc_point_here(void);
#define CAMLnoalloc                          \
  int caml__noalloc                          \
  __attribute__((cleanup(caml_noalloc_end),unused)) \
    = caml_noalloc_begin()
#define CAMLalloc_point_here (caml_alloc_point_here())
#else
#define CAMLnoalloc
#define CAMLalloc_point_here ((void)0)
#endif

#define Is_power_of_2(x) ((x) > 0 && ((x) & ((x) - 1)) == 0)

#endif

/* This hook is called when a fatal error occurs in the OCaml
   runtime. It is given arguments to be passed to the [vprintf]-like
   functions in order to synthesize the error message.
   If it returns, the runtime calls [abort()].

   If it is [NULL], the error message is printed on stderr and then
   [abort()] is called.

   This function must be reentrant. */
#ifndef __cplusplus
typedef void (*fatal_error_hook) (char *msg, va_list args);
extern _Atomic fatal_error_hook caml_fatal_error_hook;
#endif

CAMLnoret CAMLextern void caml_fatal_error (char *, ...)
#ifdef __GNUC__
  __attribute__ ((format (printf, 1, 2)))
#endif
;

CAMLnoreturn_start
CAMLextern void caml_fatal_out_of_memory (void)
CAMLnoreturn_end;

/* Detection of available C built-in functions, the Clang way. */

#ifdef __has_builtin
#define Caml_has_builtin(x) __has_builtin(x)
#else
#define Caml_has_builtin(x) 0
#endif

/* Integer arithmetic with overflow detection.
   The functions return 0 if no overflow, 1 if overflow.
   The result of the operation is always stored at [*res].
   If no overflow is reported, this is the exact result.
   If overflow is reported, this is the exact result modulo 2 to the word size.
*/

Caml_inline int caml_uadd_overflow(uintnat a, uintnat b, uintnat * res)
{
#if __GNUC__ >= 5 || Caml_has_builtin(__builtin_add_overflow)
  return __builtin_add_overflow(a, b, res);
#else
  uintnat c = a + b;
  *res = c;
  return c < a;
#endif
}

Caml_inline int caml_usub_overflow(uintnat a, uintnat b, uintnat * res)
{
#if __GNUC__ >= 5 || Caml_has_builtin(__builtin_sub_overflow)
  return __builtin_sub_overflow(a, b, res);
#else
  uintnat c = a - b;
  *res = c;
  return a < b;
#endif
}

#if __GNUC__ >= 5 || Caml_has_builtin(__builtin_mul_overflow)
Caml_inline int caml_umul_overflow(uintnat a, uintnat b, uintnat * res)
{
  return __builtin_mul_overflow(a, b, res);
}
#else
extern int caml_umul_overflow(uintnat a, uintnat b, uintnat * res);
#endif

/* From floats.c */
extern double caml_log1p(double);

/* Windows Unicode support */

#ifdef _WIN32

#ifdef CAML_INTERNALS
#define T(x) L ## x

#define main_os wmain
#endif

#define access_os _waccess
#define open_os _wopen
#define stat_os _wstati64
#define unlink_os _wunlink
#define rename_os caml_win32_rename
#define chdir_os _wchdir
#define mkdir_os(path, perm) _wmkdir(path)
#define getcwd_os _wgetcwd
#define system_os _wsystem
#define rmdir_os _wrmdir
#define putenv_os _wputenv
#define chmod_os _wchmod
#define execv_os _wexecv
#define execve_os _wexecve
#define execvp_os _wexecvp
#define execvpe_os _wexecvpe
#define strcmp_os wcscmp
#define strlen_os wcslen
#define sscanf_os swscanf
#define strcpy_os wcscpy
#define mktemp_os _wmktemp
#define fopen_os _wfopen

#define clock_os caml_win32_clock

#define caml_stat_strdup_os caml_stat_wcsdup
#define caml_stat_strdup_noexc_os caml_stat_wcsdup_noexc
#define caml_stat_strconcat_os caml_stat_wcsconcat

#define caml_stat_strdup_to_os caml_stat_strdup_to_utf16
#define caml_stat_strdup_of_os caml_stat_strdup_of_utf16
#define caml_stat_strdup_noexc_of_os caml_stat_strdup_noexc_of_utf16
#define caml_copy_string_of_os caml_copy_string_of_utf16

#else /* _WIN32 */

#ifdef CAML_INTERNALS
#define T(x) x

#define main_os main
#endif

#define access_os access
#define open_os open
#define stat_os stat
#define unlink_os unlink
#define rename_os rename
#define chdir_os chdir
#define mkdir_os mkdir
#define getcwd_os getcwd
#define system_os system
#define rmdir_os rmdir
#define putenv_os putenv
#define chmod_os chmod
#define execv_os execv
#define execve_os execve
#define execvp_os execvp
#define execvpe_os execvpe
#define strcmp_os strcmp
#define strlen_os strlen
#define sscanf_os sscanf
#define strcpy_os strcpy
#define mktemp_os mktemp
#define fopen_os fopen

#define clock_os clock

#define caml_stat_strdup_os caml_stat_strdup
#define caml_stat_strdup_noexc_os caml_stat_strdup_noexc
#define caml_stat_strconcat_os caml_stat_strconcat

#define caml_stat_strdup_to_os caml_stat_strdup
#define caml_stat_strdup_of_os caml_stat_strdup
#define caml_stat_strdup_noexc_of_os caml_stat_strdup_noexc
#define caml_copy_string_of_os caml_copy_string

#endif /* _WIN32 */

/* Wrapper for Windows unlink */
#ifdef _WIN32
#define caml_unlink caml_win32_unlink
#else
#define caml_unlink unlink_os
#endif


/* Data structures */

struct ext_table {
  int size;
  int capacity;
  void ** contents;
};

extern void caml_ext_table_init(struct ext_table * tbl, int init_capa);
extern int caml_ext_table_add(struct ext_table * tbl, void * data);
extern int caml_ext_table_add_noexc(struct ext_table * tbl, void * data);
extern void caml_ext_table_remove(struct ext_table * tbl, void * data);
extern void caml_ext_table_free(struct ext_table * tbl, int free_entries);
extern void caml_ext_table_clear(struct ext_table * tbl, int free_entries);

/* Add to [contents] the (short) names of the files contained in
   the directory named [dirname].  No entries are added for [.] and [..].
   Return 0 on success, -1 on error; set errno in the case of error. */
CAMLextern int caml_read_directory(char_os * dirname,
                                   struct ext_table * contents);

/* Deprecated aliases */
#define caml_aligned_malloc \
   CAML_DEPRECATED("caml_aligned_malloc", "caml_stat_alloc_aligned_noexc") \
   caml_stat_alloc_aligned_noexc
#define caml_strdup \
   CAML_DEPRECATED("caml_strdup", "caml_stat_strdup") \
   caml_stat_strdup
#define caml_strconcat \
   CAML_DEPRECATED("caml_strconcat", "caml_stat_strconcat") \
   caml_stat_strconcat

#ifdef CAML_INTERNALS

/* runtime message flags. Settable with v= in OCAMLRUNPARAM */

extern atomic_uintnat caml_verb_gc;

/* Bits which may be set in caml_verb_gc. Keep in sync with the OCaml
 * manual, the ocamlrun.1 man page, and gc.mli */

/* Main events of each major GC cycle */
#define CAML_GC_MSG_MAJOR           0x00001
/* Minor collection events */
#define CAML_GC_MSG_MINOR           0x00002
/* Per-slice events */
#define CAML_GC_MSG_SLICE           0x00004
/* Heap compaction */
#define CAML_GC_MSG_COMPACT         0x00008
/* GC policy computations */
#define CAML_GC_MSG_POLICY          0x00010
/* Address space reservation changes */
#define CAML_GC_MSG_ADDRSPACE       0x00020
/* Major domain events (such as creation and termination) */
#define CAML_GC_MSG_DOMAIN          0x00040
/* Stop-the-world events */
#define CAML_GC_MSG_STW             0x00080
/* Minor heap events (such as creation and resizing) */
#define CAML_GC_MSG_MINOR_HEAP      0x00100
/* Major heap events (such as creation and teardown) */
#define CAML_GC_MSG_MAJOR_HEAP      0x00200
/* Resizing of GC tables */
#define CAML_GC_MSG_TABLES          0x00400
/* Allocation and resizing of stacks */
#define CAML_GC_MSG_STACKS          0x00800
/* Output GC statistics at program exit */
#define CAML_GC_MSG_STATS           0x01000
/* Change of GC parameters */
#define CAML_GC_MSG_PARAMS          0x02000
/* Calling of finalization functions */
#define CAML_GC_MSG_FINALIZE        0x04000
/* Bytecode executable and shared library search at start-up */
#define CAML_GC_MSG_STARTUP         0x08000
/* GC debugging messages */
#define CAML_GC_MSG_DEBUG           0x10000
/* Changes to the major GC mark stack */
#define CAML_GC_MSG_MARK_STACK      0x20000
/* Do not include timestamp and domain ID in log messages */
#define CAML_GC_MSG_NO_TIMESTAMP    0x10000000

/* Default set of messages when runtime invoked with -v */

#define CAML_GC_MSG_VERBOSE (CAML_GC_MSG_MAJOR           | \
                             CAML_GC_MSG_DOMAIN          | \
                             CAML_GC_MSG_COMPACT)

/* Use to control messages which should be output at any non-zero verbosity */

#define CAML_GC_MSG_ANY (-1)

/* output message if caml_verb_gc includes any bits in `category`. */

void caml_gc_message (int category, const char *, ...)
#if __has_attribute(format) || defined(__GNUC__)
  __attribute__ ((format (printf, 2, 3)))
#endif
;

/* Short-hand for calls to `caml_gc_message` */

#define CAML_GC_MESSAGE(category, ...) \
    caml_gc_message(CAML_GC_MSG_ ## category, __VA_ARGS__)

/* Output message if CAML_GC_MSG_DEBUG is set */

void caml_gc_log (const char *, ...)
#if __has_attribute(format) || defined(__GNUC__)
  __attribute__ ((format (printf, 1, 2)))
#endif
;

/* Runtime warnings */
extern uintnat caml_runtime_warnings;
int caml_runtime_warnings_active(void);

#ifdef DEBUG
#ifdef ARCH_SIXTYFOUR
#define Debug_tag(x) (0xD700D7D7D700D6D7ull \
                      | ((uintnat) (x) << 16) \
                      | ((uintnat) (x) << 48))
#define Is_debug_tag(x) (((x) & 0xff00ffffff00ffffull) == 0xD700D7D7D700D6D7ull)
#else
#define Debug_tag(x) (0xD700D6D7ul | ((uintnat) (x) << 16))
#define Is_debug_tag(x) (((x) & 0xff00fffful) == 0xD700D6D7ul)
#endif /* ARCH_SIXTYFOUR */

/*
  00 -> free words in minor heap
  01 -> fields of free list blocks in major heap
  03 -> heap chunks deallocated by heap shrinking
  04 -> fields deallocated by caml_obj_truncate, which is no longer available
  05 -> unused child pointers in large free blocks
  10 -> uninitialised fields of minor objects
  11 -> uninitialised fields of major objects
  15 -> uninitialised words of [caml_stat_alloc_aligned] blocks
  85 -> filler bytes of [caml_stat_alloc_aligned]
  99 -> the magic prefix of a memory block allocated by [caml_stat_alloc]

  special case (byte by byte):
  D7 -> uninitialised words of [caml_stat_alloc] blocks
*/
#define Debug_free_minor     Debug_tag (0x00)
#define Debug_free_major     Debug_tag (0x01)
#define Debug_free_shrink    Debug_tag (0x03)
#define Debug_free_truncate  Debug_tag (0x04) /* obsolete */
#define Debug_free_unused    Debug_tag (0x05)
#define Debug_free_local     Debug_tag (0x06)
#define Debug_uninit_minor   Debug_tag (0x10)
#define Debug_uninit_major   Debug_tag (0x11)
#define Debug_uninit_align   Debug_tag (0x15)
#define Debug_uninit_local   Debug_tag (0x16)
#define Debug_filler_align   Debug_tag (0x85)
#define Debug_pool_magic     Debug_tag (0x99)

#define Debug_uninit_stat    0xD7

#endif /* DEBUG */


/* snprintf emulation for Win32 */

#ifdef _WIN32
#ifndef _UCRT
extern int caml_snprintf(char * buf, size_t size, const char * format, ...);
#define snprintf caml_snprintf
#endif

CAMLextern int caml_snwprintf(wchar_t * buf,
                          size_t size,
                          const wchar_t * format, ...);
#define snprintf_os caml_snwprintf
#else
#define snprintf_os snprintf
#endif

/* Macro used to deactivate address sanitizer on some functions. */
#define CAMLno_asan
/* __has_feature is Clang-specific, but GCC defines __SANITIZE_ADDRESS__ and
 * __SANITIZE_THREAD__. */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    undef CAMLno_asan
#    define CAMLno_asan __attribute__((no_sanitize("address")))
#  endif
#else
#  if defined(__SANITIZE_ADDRESS__)
#    undef CAMLno_asan
#    define CAMLno_asan __attribute__((no_sanitize_address))
#  endif
#endif

/* Generate a named symbol that is unique within the current macro expansion */
#define CAML_GENSYM_3(name, l) caml__##name##_##l
#define CAML_GENSYM_2(name, l) CAML_GENSYM_3(name, l)
#define CAML_GENSYM(name) CAML_GENSYM_2(name, __LINE__)

#endif /* CAML_INTERNALS */

/* The [backtrace_slot] type represents values stored in
 * [Caml_state->backtrace_buffer].  In bytecode, it is the same as a
 * [code_t], in native code it is either a [frame_descr *] or a [debuginfo],
 * depending on the second-lowest bit.  In any case, the lowest bit must
 * be 0.
 * The representation doesn't matter for code outside [backtrace_{byt,nat}.c],
 * so it is just exposed as a [void *].
 */
typedef void * backtrace_slot;

#ifdef __cplusplus
}
#endif

#endif /* CAML_MISC_H */
