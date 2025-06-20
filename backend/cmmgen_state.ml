(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                     Mark Shinwell, Jane Street Europe                  *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*   Copyright 2019 Jane Street Group LLC                                 *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

[@@@ocaml.warning "+a-40-41-42"]

open! Int_replace_polymorphic_compare
module S = Misc.Stdlib.String

type ustructured_constant =
  | Const_float32 of float
  | Const_float of float
  | Const_int32 of int32
  | Const_int64 of int64
  | Const_nativeint of nativeint
  | Const_vec128 of
      { word0 : int64; (* Least significant *)
        word1 : int64
      }
  | Const_vec256 of
      { word0 : int64; (* Least significant *)
        word1 : int64;
        word2 : int64;
        word3 : int64
      }
  | Const_vec512 of
      { word0 : int64; (* Least significant *)
        word1 : int64;
        word2 : int64;
        word3 : int64;
        word4 : int64;
        word5 : int64;
        word6 : int64;
        word7 : int64
      }
  | Const_block of int * uconstant list
  | Const_float_array of float list
  | Const_string of string

and uconstant =
  | Const_ref of string * ustructured_constant option
  | Const_int of int

(* Comparison functions for constants. We must not use Stdlib.compare because it
   compares "0.0" and "-0.0" equal. (PR#6442) *)

let compare_floats x1 x2 =
  Int64.compare (Int64.bits_of_float x1) (Int64.bits_of_float x2)

let rec compare_float_lists l1 l2 =
  match l1, l2 with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | h1 :: t1, h2 :: t2 ->
    let c = compare_floats h1 h2 in
    if c <> 0 then c else compare_float_lists t1 t2

let compare_constants c1 c2 =
  match c1, c2 with
  | Const_ref (lbl1, _c1), Const_ref (lbl2, _c2) ->
    String.compare lbl1 lbl2
    (* Same labels -> same constants. Different labels -> different constants,
       even if the contents match, because of string constants that must not be
       reshared. *)
  | Const_int n1, Const_int n2 -> Stdlib.compare n1 n2
  | Const_ref _, _ -> -1
  | Const_int _, Const_ref _ -> 1

let rec compare_constant_lists l1 l2 =
  match l1, l2 with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | h1 :: t1, h2 :: t2 ->
    let c = compare_constants h1 h2 in
    if c <> 0 then c else compare_constant_lists t1 t2

let rank_structured_constant = function
  | Const_float _ -> 0
  | Const_int32 _ -> 1
  | Const_int64 _ -> 2
  | Const_nativeint _ -> 3
  | Const_block _ -> 4
  | Const_float_array _ -> 5
  | Const_string _ -> 6
  | Const_vec128 _ -> 7
  | Const_vec256 _ -> 8
  | Const_vec512 _ -> 9
  | Const_float32 _ -> 10

let compare_structured_constants c1 c2 =
  match c1, c2 with
  | Const_float x1, Const_float x2 -> compare_floats x1 x2
  | Const_int32 x1, Const_int32 x2 -> Int32.compare x1 x2
  | Const_int64 x1, Const_int64 x2 -> Int64.compare x1 x2
  | Const_nativeint x1, Const_nativeint x2 -> Nativeint.compare x1 x2
  | Const_block (t1, l1), Const_block (t2, l2) ->
    let c = t1 - t2 (* no overflow possible here *) in
    if c <> 0 then c else compare_constant_lists l1 l2
  | Const_float_array l1, Const_float_array l2 -> compare_float_lists l1 l2
  | Const_string s1, Const_string s2 -> String.compare s1 s2
  | ( Const_vec128 { word0 = l0; word1 = l1 },
      Const_vec128 { word0 = r0; word1 = r1 } ) ->
    Misc.Stdlib.Array.compare Int64.compare [| l0; l1 |] [| r0; r1 |]
  | ( Const_vec256 { word0 = l0; word1 = l1; word2 = l2; word3 = l3 },
      Const_vec256 { word0 = r0; word1 = r1; word2 = r2; word3 = r3 } ) ->
    Misc.Stdlib.Array.compare Int64.compare [| l0; l1; l2; l3 |]
      [| r0; r1; r2; r3 |]
  | ( Const_vec512
        { word0 = l0;
          word1 = l1;
          word2 = l2;
          word3 = l3;
          word4 = l4;
          word5 = l5;
          word6 = l6;
          word7 = l7
        },
      Const_vec512
        { word0 = r0;
          word1 = r1;
          word2 = r2;
          word3 = r3;
          word4 = r4;
          word5 = r5;
          word6 = r6;
          word7 = r7
        } ) ->
    Misc.Stdlib.Array.compare Int64.compare
      [| l0; l1; l2; l3; l4; l5; l6; l7 |]
      [| r0; r1; r2; r3; r4; r5; r6; r7 |]
  | ( ( Const_string _ | Const_float _ | Const_int32 _ | Const_int64 _
      | Const_nativeint _ | Const_block _ | Const_float_array _ | Const_vec128 _
      | Const_vec256 _ | Const_vec512 _ | Const_float32 _ ),
      _ ) ->
    (* no overflow possible here *)
    rank_structured_constant c1 - rank_structured_constant c2

type constant = Const_table of Cmm.is_global * Cmm.data_item list

type t =
  { mutable constants : constant S.Map.t;
    mutable data_items : Cmm.data_item list list;
    structured_constants :
      (string, Cmm.is_global * ustructured_constant) Hashtbl.t
  }

let empty =
  { constants = S.Map.empty;
    data_items = [];
    structured_constants = Hashtbl.create 16
  }

let state = empty

let add_constant sym cst = state.constants <- S.Map.add sym cst state.constants

let add_data_items items = state.data_items <- items :: state.data_items

let get_and_clear_constants () =
  let constants = state.constants in
  state.constants <- S.Map.empty;
  constants

let get_and_clear_data_items () =
  let data_items = List.concat (List.rev state.data_items) in
  state.data_items <- [];
  data_items

let add_structured_constant (sym : Cmm.symbol) cst =
  if not (Hashtbl.mem state.structured_constants sym.sym_name)
  then
    Hashtbl.replace state.structured_constants sym.sym_name (sym.sym_global, cst)

let clear_local_structured_constants () =
  Hashtbl.clear state.structured_constants

let add_global_structured_constant sym cst =
  if not (Hashtbl.mem state.structured_constants sym)
  then Hashtbl.replace state.structured_constants sym (Cmm.Global, cst)

let get_structured_constant s = Hashtbl.find_opt state.structured_constants s

let structured_constant_of_sym s =
  Option.map snd (Hashtbl.find_opt state.structured_constants s)
