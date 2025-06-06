# 2 "gc.ml"
(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*            Damien Doligez, projet Para, INRIA Rocquencourt             *)
(*            Jacques-Henri Jourdan, projet Gallium, INRIA Paris          *)
(*                                                                        *)
(*   Copyright 1996-2016 Institut National de Recherche en Informatique   *)
(*     et en Automatique.                                                 *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open! Stdlib

[@@@ocaml.flambda_o3]

type stat = {
  minor_words : float;
  promoted_words : float;
  major_words : float;
  minor_collections : int;
  major_collections : int;
  heap_words : int;
  heap_chunks : int;
  live_words : int;
  live_blocks : int;
  free_words : int;
  free_blocks : int;
  largest_free : int;
  fragments : int;
  compactions : int;
  top_heap_words : int;
  stack_size : int;
  forced_major_collections: int;
}

type control = {
  minor_heap_size : int;
  major_heap_increment : int;
  space_overhead : int;
  verbose : int;
  max_overhead : int;
  stack_limit : int;
  allocation_policy : int;
  window_size : int;
  custom_major_ratio : int;
  custom_minor_ratio : int;
  custom_minor_max_size : int;
}

external stat : unit -> stat @@ portable = "caml_gc_stat"
external quick_stat : unit -> stat @@ portable = "caml_gc_quick_stat"
external counters : unit -> (float * float * float) @@ portable = "caml_gc_counters"
external minor_words : unit -> (float [@unboxed]) @@ portable
  = "caml_gc_minor_words" "caml_gc_minor_words_unboxed"
external get : unit -> control @@ portable = "caml_gc_get"
external set : control -> unit @@ portable = "caml_gc_set"
external minor : unit -> unit @@ portable = "caml_gc_minor"
external major_slice : int -> int @@ portable = "caml_gc_major_slice"
external major : unit -> unit @@ portable = "caml_gc_major"
external full_major : unit -> unit @@ portable = "caml_gc_full_major"
external compact : unit -> unit @@ portable = "caml_gc_compaction"
external get_minor_free : unit -> int @@ portable = "caml_get_minor_free"

(* CR ocaml 5 all-runtime5: These functions are no-ops upstream. We should
   make them no-ops internally when we delete the corresponding C functions
   from the runtime -- they're already marked as deprecated in the mli.
*)

external eventlog_pause : unit -> unit @@ portable = "caml_eventlog_pause"
external eventlog_resume : unit -> unit @@ portable = "caml_eventlog_resume"

open Printf

let print_stat c =
  let st = stat () in
  fprintf c "minor_collections:      %d\n" st.minor_collections;
  fprintf c "major_collections:      %d\n" st.major_collections;
  fprintf c "compactions:            %d\n" st.compactions;
  fprintf c "forced_major_collections: %d\n" st.forced_major_collections;
  fprintf c "\n";
  let l1 = String.length (sprintf "%.0f" st.minor_words) in
  fprintf c "minor_words:    %*.0f\n" l1 st.minor_words;
  fprintf c "promoted_words: %*.0f\n" l1 st.promoted_words;
  fprintf c "major_words:    %*.0f\n" l1 st.major_words;
  fprintf c "\n";
  let l2 = String.length (sprintf "%d" st.top_heap_words) in
  fprintf c "top_heap_words: %*d\n" l2 st.top_heap_words;
  fprintf c "heap_words:     %*d\n" l2 st.heap_words;
  fprintf c "live_words:     %*d\n" l2 st.live_words;
  fprintf c "free_words:     %*d\n" l2 st.free_words;
  fprintf c "largest_free:   %*d\n" l2 st.largest_free;
  fprintf c "fragments:      %*d\n" l2 st.fragments;
  fprintf c "\n";
  fprintf c "live_blocks: %d\n" st.live_blocks;
  fprintf c "free_blocks: %d\n" st.free_blocks;
  fprintf c "heap_chunks: %d\n" st.heap_chunks


let allocated_bytes () =
  let (mi, pro, ma) = counters () in
  (mi +. ma -. pro) *. float_of_int (Sys.word_size / 8)


external finalise : ('a -> unit) -> 'a -> unit = "caml_final_register"
external finalise_last : (unit -> unit) -> 'a -> unit =
  "caml_final_register_called_without_value"
external finalise_release : unit -> unit @@ portable = "caml_final_release"


type alarm = bool Atomic.t Modes.Contended.t
type alarm_rec = {active : alarm; f : unit -> unit}

let rec call_alarm arec =
  if Atomic.Contended.get arec.active.contended then begin
    let finally () = finalise call_alarm arec in
    Fun.protect ~finally arec.f
  end

let delete_alarm a = Atomic.Contended.set a.Modes.Contended.contended false

(* We use [@inline never] to ensure [arec] is never statically allocated
   (which would prevent installation of the finaliser). *)
let [@inline never] create_alarm f =
  let alarm = { Modes.Contended.contended = (Atomic.make true : bool Atomic.t) } in
  Domain.at_exit (fun () -> delete_alarm alarm);
  let arec = { active = alarm; f = f } in
  finalise call_alarm arec;
  alarm

module Safe = struct
  external finalise
    : ('a @ portable contended -> unit) @ portable -> 'a @ portable contended -> unit
    @@ portable
    = "caml_final_register"

  external finalise_last : (unit -> unit) @ portable -> 'a -> unit @@ portable =
    "caml_final_register_called_without_value"

  let rec call_alarm (arec : alarm_rec) =
    if Atomic.Contended.get arec.active.contended then begin
      let finally () = finalise call_alarm arec in
      Fun.protect ~finally arec.f
    end

  (* We use [@inline never] to ensure [arec] is never statically allocated
     (which would prevent installation of the finaliser). *)
  let [@inline never] create_alarm f =
    let alarm = { Modes.Contended.contended = (Atomic.make true : bool Atomic.t) } in
    Domain.Safe.at_exit (fun () -> delete_alarm alarm);
    let arec = { active = alarm; f = f } in
    finalise call_alarm arec;
    alarm
end

module Memprof =
  struct
    type t
    type allocation_source = Normal | Marshal | Custom
    type allocation =
      { n_samples : int;
        size : int;
        source : allocation_source;
        callstack : Printexc.raw_backtrace }

    type ('minor, 'major) tracker = {
      alloc_minor: allocation -> 'minor option;
      alloc_major: allocation -> 'major option;
      promote: 'minor -> 'major option;
      dealloc_minor: 'minor -> unit;
      dealloc_major: 'major -> unit;
    }

    let null_tracker = {
      alloc_minor = (fun _ -> None);
      alloc_major = (fun _ -> None);
      promote = (fun _ -> None);
      dealloc_minor = (fun _ -> ());
      dealloc_major = (fun _ -> ());
    }

    external c_start :
      float -> int -> ('minor, 'major) tracker -> t
      = "caml_memprof_start"

    let start
      ~sampling_rate
      ?(callstack_size = max_int)
      tracker =
      c_start sampling_rate callstack_size tracker

    module Safe = struct
      external c_start :
        float -> int -> ('minor, 'major) tracker -> t @@ portable
        = "caml_memprof_start"

      let start
        ~sampling_rate
        ?(callstack_size = max_int)
        tracker =
        c_start sampling_rate callstack_size tracker

      let start'
        (_ : Domain.Safe.DLS.Access.t)
        ~sampling_rate
        ?(callstack_size = max_int)
        tracker =
        c_start sampling_rate callstack_size tracker
    end

    external stop : unit -> unit @@ portable = "caml_memprof_stop"

    external discard : t -> unit @@ portable = "caml_memprof_discard"
  end

module Tweak = struct
  external set : string -> int -> unit = "caml_gc_tweak_set"
  external get : string -> int = "caml_gc_tweak_get"
  external list_active : unit -> (string * int) list = "caml_gc_tweak_list_active"
end
