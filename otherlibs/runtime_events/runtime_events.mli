(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                          Sadiq Jaffer, Opsian                          *)
(*                                                                        *)
(*   Copyright 2021 Opsian Ltd                                            *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Runtime events - ring buffer-based runtime tracing

    This module enables users to enable and subscribe to tracing events
    from the Garbage Collector and other parts of the OCaml runtime. This can
    be useful for diagnostic or performance monitoring purposes. This module
    can be used to subscribe to events for the current process or external
    processes asynchronously.

    When enabled (either via setting the OCAML_RUNTIME_EVENTS_START environment
    variable or calling Runtime_events.start) a file with the pid of the process
    and extension .events will be created. By default this is in the
    current directory but can be over-ridden by the OCAML_RUNTIME_EVENTS_DIR
    environment variable. Each domain maintains its own ring buffer in a section
    of the larger file into which it emits events.

    There is additionally a set of C APIs in runtime_events.h that can enable
    zero-impact monitoring of the current process or bindings for other
    languages.

    The runtime events system's behaviour can be controlled by the following
    environment variables:

    - OCAML_RUNTIME_EVENTS_START if set will cause the runtime events system
    to be started as part of the OCaml runtime initialization.

    - OCAML_RUNTIME_EVENTS_DIR sets the directory where the runtime events
    ring buffers will be located. If not present the program's working directory
    will be used.

  - OCAML_RUNTIME_EVENTS_PRESERVE if set will prevent the OCaml runtime from
    removing its ring buffers when it terminates. This can help if monitoring
    very short running programs.
*)

(** The type for counter events emitted by the runtime. *)
type runtime_counter =
| EV_C_FORCE_MINOR_ALLOC_SMALL
| EV_C_FORCE_MINOR_MAKE_VECT
| EV_C_FORCE_MINOR_SET_MINOR_HEAP_SIZE
| EV_C_FORCE_MINOR_MEMPROF
| EV_C_MINOR_PROMOTED
| EV_C_MINOR_ALLOCATED
| EV_C_REQUEST_MAJOR_ALLOC_SHR
| EV_C_REQUEST_MAJOR_ADJUST_GC_SPEED
| EV_C_REQUEST_MINOR_REALLOC_REF_TABLE
| EV_C_REQUEST_MINOR_REALLOC_EPHE_REF_TABLE
| EV_C_REQUEST_MINOR_REALLOC_CUSTOM_TABLE
| EV_C_MAJOR_HEAP_POOL_WORDS
(**
Total words in a Domain's major heap pools. This is the sum of unallocated and
live words in each pool.
@since 5.1 *)
| EV_C_MAJOR_HEAP_POOL_LIVE_WORDS
(**
Current live words in a Domain's major heap pools.
@since 5.1 *)
| EV_C_MAJOR_HEAP_LARGE_WORDS
(**
Total words of a Domain's major heap large allocations.
A large allocation is an allocation larger than the largest sized pool.
@since 5.1 *)
| EV_C_MAJOR_HEAP_POOL_FRAG_WORDS
(**
Words in a Domain's major heap pools lost to fragmentation. This is due to
there not being a pool with the exact size of an allocation and a larger sized
pool needing to be used.
@since 5.1 *)
| EV_C_MAJOR_HEAP_POOL_LIVE_BLOCKS
(**
Live blocks of a Domain's major heap pools.
@since 5.1 *)
| EV_C_MAJOR_HEAP_LARGE_BLOCKS
(**
Live blocks of a Domain's major heap large allocations.
@since 5.1 *)
| EV_C_REQUEST_MINOR_REALLOC_DEPENDENT_TABLE
(**
   Reallocation of the table of dependent memory from minor heap
@since 5.4 *)
| EV_C_MAJOR_SLICE_ALLOC_WORDS
(**
Words of heap allocation by this domain since the last major slice
@since 5.4 *)
| EV_C_MAJOR_SLICE_ALLOC_DEPENDENT_WORDS
(**
Words of off-heap allocation by this domain since the last major slice
@since 5.4 *)
| EV_C_MAJOR_SLICE_NEW_WORK
(**
New GC work incurred by this domain since the last major slice
@since 5.4 *)
| EV_C_MAJOR_SLICE_TOTAL_WORK
(**
Total pending GC work (for all domains) at start of slice
@since 5.4 *)
| EV_C_MAJOR_SLICE_BUDGET
(**
Work budget for this domain in the current slice
@since 5.4 *)
| EV_C_MAJOR_SLICE_WORK_DONE
(**
Total work done by this domain in a slice
@since 5.4 *)

(** The type for span events emitted by the runtime. *)
type runtime_phase =
| EV_EXPLICIT_GC_SET
| EV_EXPLICIT_GC_STAT
| EV_EXPLICIT_GC_MINOR
| EV_EXPLICIT_GC_MAJOR
| EV_EXPLICIT_GC_FULL_MAJOR
| EV_EXPLICIT_GC_COMPACT
| EV_MAJOR
| EV_MAJOR_SWEEP
| EV_MAJOR_MARK_ROOTS
| EV_MAJOR_MEMPROF_ROOTS
| EV_MAJOR_MARK
| EV_MINOR
| EV_MINOR_LOCAL_ROOTS
| EV_MINOR_MEMPROF_ROOTS
| EV_MINOR_MEMPROF_CLEAN
| EV_MINOR_FINALIZED
| EV_EXPLICIT_GC_MAJOR_SLICE
| EV_FINALISE_UPDATE_FIRST
| EV_FINALISE_UPDATE_LAST
| EV_INTERRUPT_REMOTE
| EV_MAJOR_EPHE_MARK
| EV_MAJOR_EPHE_SWEEP
| EV_MAJOR_FINISH_MARKING
| EV_MAJOR_GC_CYCLE_DOMAINS
| EV_MAJOR_GC_PHASE_CHANGE
| EV_MAJOR_GC_STW
| EV_MAJOR_MARK_OPPORTUNISTIC
| EV_MAJOR_SLICE
| EV_MAJOR_FINISH_CYCLE
| EV_MINOR_CLEAR
| EV_MINOR_FINALIZERS_OLDIFY
| EV_MINOR_GLOBAL_ROOTS
| EV_MINOR_LEAVE_BARRIER
| EV_STW_API_BARRIER
| EV_STW_HANDLER
| EV_STW_LEADER
| EV_MAJOR_FINISH_SWEEPING
| EV_MAJOR_MEMPROF_CLEAN
| EV_MINOR_FINALIZERS_ADMIN
| EV_MINOR_REMEMBERED_SET
| EV_MINOR_REMEMBERED_SET_PROMOTE
| EV_MINOR_LOCAL_ROOTS_PROMOTE
| EV_DOMAIN_CONDITION_WAIT
| EV_DOMAIN_RESIZE_HEAP_RESERVATION
| EV_COMPACT
| EV_COMPACT_EVACUATE
| EV_COMPACT_FORWARD
| EV_COMPACT_RELEASE
| EV_MINOR_EPHE_CLEAN
| EV_MINOR_DEPENDENT

(** Lifecycle events for the ring itself. *)
type lifecycle =
  EV_RING_START
| EV_RING_STOP
| EV_RING_PAUSE
| EV_RING_RESUME
| EV_FORK_PARENT
| EV_FORK_CHILD
| EV_DOMAIN_SPAWN
| EV_DOMAIN_TERMINATE

val lifecycle_name : lifecycle -> string
(** Return a string representation of a given lifecycle event type. *)

val runtime_phase_name : runtime_phase -> string
(** Return a string representation of a given runtime phase event type. *)

val runtime_counter_name : runtime_counter -> string
(** Return a string representation of a given runtime counter type. *)

type cursor
(** Type of the cursor used when consuming. *)

module Timestamp : sig
    type t
    (** Type for the int64 timestamp to allow for future changes. *)

    val to_int64 : t -> int64
end

module Type : sig
  type 'a t
  (** The type for a user event content type. *)

  val unit : unit t
  (** An event that has no data associated with it. *)

  type span = Begin | End

  val span : span t
  (** An event that has a beginning and an end. *)

  val int : int t
  (** An event containing an integer value. *)

  val register : encode:(bytes -> 'a -> int) -> decode:(bytes -> int -> 'a)
                                                                        -> 'a t
  (** Registers a custom type by providing an encoder and a decoder. The encoder
      writes the value in the provided buffer and returns the number of bytes
      written. The decoder gets a slice of the buffer of specified length, and
      returns the decoded value.

      The maximum value length is 1024 bytes. *)
end

module User : sig
  (** User events is a way for libraries to provide runtime events that can be
      consumed by other tools. These events can carry known data types or custom
      values. The current maximum number of user events is 8192. *)

  type tag = ..
  (** The type for a user event tag. Tags are used to discriminate between
      user events of the same type. *)

  type 'value t
  (** The type for a user event. User events describe their tag, carried data
      type and an unique string-based name. *)

  val register : string -> tag -> 'value Type.t -> 'value t
  (** [register name tag ty] registers a new event with an unique [name],
      carrying a [tag] and values of type [ty]. *)

  val write : 'value t -> 'value -> unit
  (** [write t v] emits value [v] for event [t]. *)

  val name : _ t -> string
  (** [name t] is the unique identifying name of event [t]. *)

  val tag : 'a t -> tag
  (** [tag t] is the associated tag of event [t], when it is known.
      An event can be unknown if it was not registered in the consumer
      program. *)

end

module Callbacks : sig
  type t
  (** Type of callbacks. *)

  val create : ?runtime_begin:(int -> Timestamp.t -> runtime_phase
                                -> unit) ->
             ?runtime_end:(int -> Timestamp.t -> runtime_phase
                                -> unit) ->
             ?runtime_counter:(int -> Timestamp.t -> runtime_counter
                                -> int -> unit) ->
             ?alloc:(int -> Timestamp.t -> int array -> unit) ->
             ?lifecycle:(int -> Timestamp.t -> lifecycle
                            -> int option -> unit) ->
             ?lost_events:(int -> int -> unit) -> unit -> t
  (** Create a [Callback] that optionally subscribes to one or more runtime
      events. The first int supplied to callbacks is the ring buffer index.
      Each domain owns a single ring buffer for the duration of the domain's
      existence. After a domain terminates, a newly spawned domain may take
      ownership of the ring buffer. A [runtime_begin] callback is called when
      the runtime enters a new phase (e.g a runtime_begin with EV_MINOR is
      called at the start of a minor GC). A [runtime_end] callback is called
      when the runtime leaves a certain phase. The [runtime_counter] callback
      is called when a counter is emitted by the runtime. [lifecycle] callbacks
      are called when the ring undergoes a change in lifecycle and a consumer
      may need to respond. [alloc] callbacks are currently only called on the
      instrumented runtime. [lost_events] callbacks are called if the consumer
      code detects some unconsumed events have been overwritten.
      *)

  val add_user_event : 'a Type.t ->
                        (int -> Timestamp.t -> 'a User.t -> 'a -> unit) ->
                        t -> t
  (** [add_user_event ty callback t] extends [t] to additionally subscribe to
      user events of type [ty]. When such an event happens, [callback] is called
      with the corresponding event and payload. *)
end

val start : unit -> unit
(** [start ()] will start the collection of events in the runtime if not already
  started.

  Events can be consumed by creating a cursor with [create_cursor] and providing
  a set of callbacks to be called for each type of event.
*)

val path : unit -> string option
(** If runtime events are being collected, [path ()] returns [Some p] where [p]
  is a path to the runtime events file. Otherwise, it returns None. *)

val pause : unit -> unit
(** [pause ()] will pause the collection of events in the runtime.
   Traces are collected if the program has called [Runtime_events.start ()] or
   the OCAML_RUNTIME_EVENTS_START environment variable has been set.
*)

val resume : unit -> unit
(** [resume ()] will resume the collection of events in the runtime.
   Traces are collected if the program has called [Runtime_events.start ()] or
   the OCAML_RUNTIME_EVENTS_START environment variable has been set.
*)

val create_cursor : (string * int) option -> cursor
(** [create_cursor path_pid] creates a cursor to read from an runtime_events.
   Cursors can be created for runtime_events in and out of process. A
   runtime_events ring-buffer may have multiple cursors reading from it at any
   point in time and a program may have multiple cursors open concurrently
  (for example if multiple consumers want different sets of events). If
   [path_pid] is None then a cursor is created for the current process.
   Otherwise the pair contains a string [path] to the directory that contains
   the [pid].events file and int [pid] for the runtime_events of an
   external process to monitor. *)

val free_cursor : cursor -> unit
(** Free a previously created runtime_events cursor. *)

val read_poll : cursor -> Callbacks.t -> int option -> int
(** [read_poll cursor callbacks max_option] calls the corresponding functions
    on [callbacks] for up to [max_option] events read off [cursor]'s
    runtime_events and returns the number of events read. *)
