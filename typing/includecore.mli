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

(* Inclusion checks for the core language *)

open Typedtree
open Types

type position = Errortrace.position = First | Second

type primitive_mismatch =
  | Name
  | Arity
  | No_alloc of position
  | Builtin
  | Effects
  | Coeffects
  | Native_name
  | Result_repr
  | Argument_repr of int
  | Layout_poly_attr

type value_mismatch =
  | Primitive_mismatch of primitive_mismatch
  | Not_a_primitive
  | Type of Errortrace.moregen_error
  | Zero_alloc of Zero_alloc.error
  | Modality of Mode.Modality.Value.error
  | Mode of Mode.Value.error

exception Dont_match of value_mismatch

(* Documents which kind of private thing would be revealed *)
type privacy_mismatch =
  | Private_type_abbreviation
  | Private_variant_type
  | Private_record_type
  | Private_record_unboxed_product_type
  | Private_extensible_variant
  | Private_row_type

type type_kind =
  | Kind_abstract
  | Kind_record
  | Kind_record_unboxed_product
  | Kind_variant
  | Kind_open

type kind_mismatch = type_kind * type_kind

type label_mismatch =
  | Type of Errortrace.equality_error
  | Mutability of position
  | Modality of Mode.Modality.Value.equate_error

type record_change =
  (Types.label_declaration as 'ld, 'ld, label_mismatch) Diffing_with_keys.change

type record_mismatch =
  | Label_mismatch of record_change list
  | Inlined_representation of position
  | Float_representation of position
  | Ufloat_representation of position
  | Mixed_representation of position
  | Mixed_representation_with_flat_floats of position

type constructor_mismatch =
  | Type of Errortrace.equality_error
  | Arity
  | Inline_record of record_change list
  | Kind of position
  | Explicit_return_type of position
  | Modality of int * Mode.Modality.Value.equate_error

type extension_constructor_mismatch =
  | Constructor_privacy
  | Constructor_mismatch of Ident.t
                            * extension_constructor
                            * extension_constructor
                            * constructor_mismatch
type variant_change =
  (Types.constructor_declaration as 'cd, 'cd, constructor_mismatch)
    Diffing_with_keys.change

type private_variant_mismatch =
  | Only_outer_closed
  | Missing of position * string
  | Presence of string
  | Incompatible_types_for of string
  | Types of Errortrace.equality_error

type private_object_mismatch =
  | Missing of string
  | Types of Errortrace.equality_error

type unsafe_mode_crossing_mismatch =
  | Mode_crossing_only_on of position
  | Bounds_not_equal of unsafe_mode_crossing * unsafe_mode_crossing

type type_mismatch =
  | Arity
  | Privacy of privacy_mismatch
  | Kind of kind_mismatch
  | Constraint of Errortrace.equality_error
  | Manifest of Errortrace.equality_error
  | Parameter_jkind of type_expr * Jkind.Violation.t
  | Private_variant of type_expr * type_expr * private_variant_mismatch
  | Private_object of type_expr * type_expr * private_object_mismatch
  | Variance
  | Record_mismatch of record_mismatch
  | Variant_mismatch of variant_change list
  | Unboxed_representation of position * attributes
  | Extensible_representation of position
  | With_null_representation of position
  | Jkind of Jkind.Violation.t
  | Unsafe_mode_crossing of unsafe_mode_crossing_mismatch

type mmodes =
  | All
  (** Check module inclusion [M1 : MT1 @ m1 <= M2 : MT2 @ m2]
      for all [m1 <= m2]. *)
  | Legacy of Env.held_locks option
  (** Check module inclusion [M1 : MT1 @ legacy <= M2 : MT2 @ legacy].
    If [M1] is a [Pmod_ident] and the current inclusion check is for its
    coercion into [M2], we treat all surroudning functions as not closing over
    [M1], but closing over components in [M1] required by [MT2]. Therefore, the
    locks for [M1] are held, to be walked by each of the components
    individually.

    This is potentially unsafe as it doesn't reflect the real runtime behavior,
    for at least two reasons:
    - The corecion might turn out to be [coercion_none], in which case no
    coercion happens, and the functions will be closing over the original module.
    - Even if the coercion happens, the functions will be closing over the
      original module and projecting needed values out of it.

    The above concern can be resolved by the "ergonomics" discussion in
    [typecore.type_ident].
  *)

val value_descriptions:
  loc:Location.t -> Env.t -> string ->
  mmodes:mmodes ->
  value_description -> value_description -> module_coercion

val type_declarations:
  ?equality:bool ->
  loc:Location.t ->
  Env.t -> mark:bool -> string ->
  type_declaration -> Path.t -> type_declaration -> type_mismatch option

val extension_constructors:
  loc:Location.t -> Env.t -> mark:bool -> Ident.t ->
  extension_constructor -> extension_constructor ->
  extension_constructor_mismatch option
(*
val class_types:
        Env.t -> class_type -> class_type -> bool
*)

val report_value_mismatch :
  string -> string ->
  Env.t ->
  Format.formatter -> value_mismatch -> unit

val report_type_mismatch :
  string -> string -> string ->
  Env.t ->
  Format.formatter -> type_mismatch -> unit

val report_extension_constructor_mismatch :
  string -> string -> string ->
  Env.t ->
  Format.formatter -> extension_constructor_mismatch -> unit
