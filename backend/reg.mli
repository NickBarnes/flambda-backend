(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Pseudo-registers *)

module Raw_name : sig
  type t
  val create_from_var : Backend_var.t -> t
  val to_string : t -> string option
end

type t =
  { mutable raw_name: Raw_name.t;         (* Name *)
    stamp: int;                           (* Unique stamp *)
    typ: Cmm.machtype_component;          (* Type of contents *)
    mutable loc: location; }              (* Actual location *)

and location =
    Unknown
  | Reg of int
  | Stack of stack_location

and stack_location =
    Local of int
  | Incoming of int
  | Outgoing of int
  | Domainstate of int

(* The [stack_location] describes the location of pseudo-registers
   that reside in memory.
 - [Local] is a local variable or spilled register residing in the stack frame
   of the current function
 - [Incoming] is a function parameter that was passed on the stack.
   This is the callee's view: the location is just above the callee's
   stack frame, in the caller's stack frame.
 - [Outgoing] is a function call argument that is passed on the stack.
   This is the caller's view: the location is at the bottom of the
   caller's stack frame.
 - [Domainstate] is a function call argument that is passed not on stack
   but in the [extra_params] section of the domain state
   (see file [../runtime/caml/domain_state.*]).  Unlike arguments passed
   on stack, arguments passed via the domain state are compatible with
   tail calls.  However, domain state locations are shared between
   all functions that run in a given domain, hence they are not preserved
   by function calls or thread context switches.  The caller stores
   arguments in the domain state immediately before the call, and the
   first thing the callee does is copy them to registers or [Local]
   stack locations.  Neither GC nor thread context switches can occur
   between these two times. *)

val equal_location : location -> location -> bool

val dummy: t
val create: Cmm.machtype_component -> t
val createv: Cmm.machtype -> t array
val createv_like: t array -> t array
val clone: t -> t
val at_location: Cmm.machtype_component -> location -> t
val typv: t array -> Cmm.machtype
val is_preassigned : t -> bool
val is_unknown : t -> bool

(* Name for printing *)
val name : t -> string

(* Check [t]'s location *)
val is_reg : t -> bool
val is_stack :  t -> bool

module Set: Set.S with type elt = t
module Map: Map.S with type key = t
module Tbl: Hashtbl.S with type key = t

val add_set_array: Set.t -> t array -> Set.t
val diff_set_array: Set.t -> t array -> Set.t
val inter_set_array: Set.t -> t array -> Set.t
val disjoint_set_array: Set.t -> t array -> bool
val set_of_array: t array -> Set.t
val set_has_collisions : Set.t -> bool

val reset: unit -> unit
val all_registers: unit -> t list
val num_registers: unit -> int
val reinit: unit -> unit

val same_phys_reg : t -> t -> bool
val same_loc : t -> t -> bool
val same : t -> t -> bool
val compare : t -> t -> int
