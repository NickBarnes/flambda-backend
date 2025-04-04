# 2 "stack.mli"
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

@@ portable

(** Last-in first-out stacks.

   This module implements stacks (LIFOs), with in-place modification.
*)

(** {b Unsynchronized accesses} *)

[@@@alert unsynchronized_access
    "Unsynchronized accesses to stacks are a programming error."
]

open! Stdlib

 (**
    Unsynchronized accesses to a stack may lead to an invalid queue state.
    Thus, concurrent accesses to stacks must be synchronized (for instance
    with a {!Mutex.t}).
*)

type (!'a : value_or_null) t : mutable_data with 'a
(** The type of stacks containing elements of type ['a]. *)

exception Empty
(** Raised when {!Stack.pop} or {!Stack.top} is applied to an empty stack. *)


val create : ('a : value_or_null) . unit -> 'a t
(** Return a new stack, initially empty. *)

val push : ('a : value_or_null) . 'a -> 'a t -> unit
(** [push x s] adds the element [x] at the top of stack [s]. *)

val pop : ('a : value_or_null) . 'a t -> 'a
(** [pop s] removes and returns the topmost element in stack [s],
   or raises {!Empty} if the stack is empty. *)

val pop_opt : ('a : value_or_null) . 'a t -> 'a option
(** [pop_opt s] removes and returns the topmost element in stack [s],
   or returns [None] if the stack is empty.
   @since 4.08 *)

val drop : ('a : value_or_null) . 'a t -> unit
(** [drop s] removes the topmost element in stack [s],
   or raises {!Empty} if the stack is empty.
   @since 5.1 *)

val top : ('a : value_or_null) . 'a t -> 'a
(** [top s] returns the topmost element in stack [s],
   or raises {!Empty} if the stack is empty. *)

val top_opt : ('a : value_or_null) . 'a t -> 'a option
(** [top_opt s] returns the topmost element in stack [s],
   or [None] if the stack is empty.
   @since 4.08 *)

val clear : ('a : value_or_null) . 'a t -> unit
(** Discard all elements from a stack. *)

val copy : ('a : value_or_null) . 'a t -> 'a t
(** Return a copy of the given stack. *)

val is_empty : ('a : value_or_null) . 'a t -> bool
(** Return [true] if the given stack is empty, [false] otherwise. *)

val length : ('a : value_or_null) . 'a t -> int
(** Return the number of elements in a stack. Time complexity O(1) *)

val iter : ('a : value_or_null) . ('a -> unit) -> 'a t -> unit
(** [iter f s] applies [f] in turn to all elements of [s],
   from the element at the top of the stack to the element at the
   bottom of the stack. The stack itself is unchanged. *)

val fold : ('acc : value_or_null) ('a : value_or_null)
  . ('acc -> 'a -> 'acc) -> 'acc -> 'a t -> 'acc
(** [fold f accu s] is [(f (... (f (f accu x1) x2) ...) xn)]
    where [x1] is the top of the stack, [x2] the second element,
    and [xn] the bottom element. The stack is unchanged.
    @since 4.03 *)

(** {1 Stacks and Sequences} *)

val to_seq : ('a : value_or_null) . 'a t -> 'a Seq.t
(** Iterate on the stack, top to bottom.
    It is safe to modify the stack during iteration.
    @since 4.07 *)

val add_seq : ('a : value_or_null) . 'a t -> 'a Seq.t -> unit
(** Add the elements from the sequence on the top of the stack.
    @since 4.07 *)

val of_seq : ('a : value_or_null) . 'a Seq.t -> 'a t
(** Create a stack from the sequence.
    @since 4.07 *)
