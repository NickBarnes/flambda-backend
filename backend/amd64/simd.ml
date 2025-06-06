(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                      Max Slater, Jane Street                           *)
(*                                                                        *)
(*   Copyright 2025 Jane Street Group LLC                                 *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

[@@@ocaml.warning "+a-40-42"]

open! Int_replace_polymorphic_compare [@@warning "-66"]
open Format
include Amd64_simd_defs

module Amd64_simd_instrs = struct
  include Amd64_simd_instrs

  let equal = Stdlib.( == )
end

type instr = Amd64_simd_instrs.instr

module Pcompare_string = struct
  type t =
    | Pcmpestra
    | Pcmpestrc
    | Pcmpestro
    | Pcmpestrs
    | Pcmpestrz
    | Pcmpistra
    | Pcmpistrc
    | Pcmpistro
    | Pcmpistrs
    | Pcmpistrz

  let equal t1 t2 =
    match t1, t2 with
    | Pcmpestra, Pcmpestra
    | Pcmpestrc, Pcmpestrc
    | Pcmpestro, Pcmpestro
    | Pcmpestrs, Pcmpestrs
    | Pcmpestrz, Pcmpestrz
    | Pcmpistra, Pcmpistra
    | Pcmpistrc, Pcmpistrc
    | Pcmpistro, Pcmpistro
    | Pcmpistrs, Pcmpistrs
    | Pcmpistrz, Pcmpistrz ->
      true
    | ( ( Pcmpestra | Pcmpestrc | Pcmpestro | Pcmpestrs | Pcmpestrz | Pcmpistra
        | Pcmpistrc | Pcmpistro | Pcmpistrs | Pcmpistrz ),
        _ ) ->
      false

  let mnemonic t =
    match t with
    | Pcmpestra -> "pcmpestra"
    | Pcmpestrc -> "pcmpestrc"
    | Pcmpestro -> "pcmpestro"
    | Pcmpestrs -> "pcmpestrs"
    | Pcmpestrz -> "pcmpestrz"
    | Pcmpistra -> "pcmpistra"
    | Pcmpistrc -> "pcmpistrc"
    | Pcmpistro -> "pcmpistro"
    | Pcmpistrs -> "pcmpistrs"
    | Pcmpistrz -> "pcmpistrz"
end

module Seq = struct
  type id =
    | Sqrtss
    | Sqrtsd
    | Roundss
    | Roundsd
    | Pcompare_string of Pcompare_string.t

  type nonrec t =
    { id : id;
      instr : Amd64_simd_instrs.instr
    }

  let sqrtss = { id = Sqrtss; instr = Amd64_simd_instrs.sqrtss }

  let sqrtsd = { id = Sqrtsd; instr = Amd64_simd_instrs.sqrtsd }

  let roundss = { id = Roundss; instr = Amd64_simd_instrs.roundss }

  let roundsd = { id = Roundsd; instr = Amd64_simd_instrs.roundsd }

  let pcmpestra =
    { id = Pcompare_string Pcmpestra; instr = Amd64_simd_instrs.pcmpestri }

  let pcmpestrc =
    { id = Pcompare_string Pcmpestrc; instr = Amd64_simd_instrs.pcmpestri }

  let pcmpestro =
    { id = Pcompare_string Pcmpestro; instr = Amd64_simd_instrs.pcmpestri }

  let pcmpestrs =
    { id = Pcompare_string Pcmpestrs; instr = Amd64_simd_instrs.pcmpestri }

  let pcmpestrz =
    { id = Pcompare_string Pcmpestrz; instr = Amd64_simd_instrs.pcmpestri }

  let pcmpistra =
    { id = Pcompare_string Pcmpistra; instr = Amd64_simd_instrs.pcmpistri }

  let pcmpistrc =
    { id = Pcompare_string Pcmpistrc; instr = Amd64_simd_instrs.pcmpistri }

  let pcmpistro =
    { id = Pcompare_string Pcmpistro; instr = Amd64_simd_instrs.pcmpistri }

  let pcmpistrs =
    { id = Pcompare_string Pcmpistrs; instr = Amd64_simd_instrs.pcmpistri }

  let pcmpistrz =
    { id = Pcompare_string Pcmpistrz; instr = Amd64_simd_instrs.pcmpistri }

  let mnemonic ({ id; _ } : t) =
    match id with
    | Sqrtss -> "sqrtss"
    | Sqrtsd -> "sqrtsd"
    | Roundss -> "roundss"
    | Roundsd -> "roundsd"
    | Pcompare_string p -> Pcompare_string.mnemonic p

  let equal { id = id0; instr = instr0 } { id = id1; instr = instr1 } =
    let return_true () =
      assert (Amd64_simd_instrs.equal instr0 instr1);
      true
    in
    match id0, id1 with
    | Sqrtss, Sqrtss | Sqrtsd, Sqrtsd | Roundss, Roundss | Roundsd, Roundsd ->
      return_true ()
    | Pcompare_string p1, Pcompare_string p2 ->
      if Pcompare_string.equal p1 p2 then return_true () else false
    | (Sqrtss | Sqrtsd | Roundss | Roundsd | Pcompare_string _), _ -> false
end

module Pseudo_instr = struct
  type t =
    | Instruction of Amd64_simd_instrs.instr
    | Sequence of Seq.t

  let equal t1 t2 =
    match t1, t2 with
    | Instruction i0, Instruction i1 -> Amd64_simd_instrs.equal i0 i1
    | Sequence s0, Sequence s1 -> Seq.equal s0 s1
    | (Instruction _ | Sequence _), _ -> false

  let print ppf t =
    match t with
    | Instruction instr -> fprintf ppf "%s" instr.mnemonic
    | Sequence seq -> fprintf ppf "[seq] %s" (Seq.mnemonic seq)
end

type operation =
  { instr : Pseudo_instr.t;
    imm : int option
  }

let instruction instr imm = { instr = Pseudo_instr.Instruction instr; imm }

let sequence instr imm = { instr = Pseudo_instr.Sequence instr; imm }

type operation_class =
  | Pure
  | Load of { is_mutable : bool }

let is_pure_operation _op = true

let class_of_operation _op = Pure

let equal_operation { instr = instr0; imm = imm0 }
    { instr = instr1; imm = imm1 } =
  Pseudo_instr.equal instr0 instr1 && Option.equal Int.equal imm0 imm1

let print_operation printreg (op : operation) ppf regs =
  Pseudo_instr.print ppf op.instr;
  Option.iter (fun imm -> fprintf ppf " %d" imm) op.imm;
  Array.iter (fun reg -> fprintf ppf " %a" printreg reg) regs

module Mem = struct
  (** Initial support for some operations with memory arguments.
      Requires 16-byte aligned memory. *)

  type sse_operation =
    | Add_f32
    | Sub_f32
    | Mul_f32
    | Div_f32

  type sse2_operation =
    | Add_f64
    | Sub_f64
    | Mul_f64
    | Div_f64

  type operation =
    | SSE of sse_operation
    | SSE2 of sse2_operation

  let class_of_operation_sse (op : sse_operation) =
    match op with
    | Add_f32 | Sub_f32 | Mul_f32 | Div_f32 -> Load { is_mutable = true }

  let class_of_operation_sse2 (op : sse2_operation) =
    match op with
    | Add_f64 | Sub_f64 | Mul_f64 | Div_f64 -> Load { is_mutable = true }

  let class_of_operation (op : operation) =
    match op with
    | SSE op -> class_of_operation_sse op
    | SSE2 op -> class_of_operation_sse2 op

  let op_name_sse (op : sse_operation) =
    match op with
    | Add_f32 -> "add_f32"
    | Sub_f32 -> "sub_f32"
    | Mul_f32 -> "mul_f32"
    | Div_f32 -> "div_f32"

  let op_name_sse2 (op : sse2_operation) =
    match op with
    | Add_f64 -> "add_f64"
    | Sub_f64 -> "sub_f64"
    | Mul_f64 -> "mul_f64"
    | Div_f64 -> "div_f64"

  let print_operation printreg printaddr (op : operation) ppf arg =
    let addr_args = Array.sub arg 1 (Array.length arg - 1) in
    let op_name =
      match op with SSE op -> op_name_sse op | SSE2 op -> op_name_sse2 op
    in
    fprintf ppf "%s %a [%a]" op_name printreg arg.(0) printaddr addr_args

  let is_pure_operation op =
    match class_of_operation op with Pure -> true | Load _ -> true

  let equal_operation_sse2 (l : sse2_operation) (r : sse2_operation) =
    match l, r with
    | Add_f64, Add_f64 | Sub_f64, Sub_f64 | Mul_f64, Mul_f64 | Div_f64, Div_f64
      ->
      true
    | (Add_f64 | Sub_f64 | Mul_f64 | Div_f64), _ -> false

  let equal_operation_sse (l : sse_operation) (r : sse_operation) =
    match l, r with
    | Add_f32, Add_f32 | Sub_f32, Sub_f32 | Mul_f32, Mul_f32 | Div_f32, Div_f32
      ->
      true
    | (Add_f32 | Sub_f32 | Mul_f32 | Div_f32), _ -> false

  let equal_operation (l : operation) (r : operation) =
    match l, r with
    | SSE l, SSE r -> equal_operation_sse l r
    | SSE2 l, SSE2 r -> equal_operation_sse2 l r
    | (SSE _ | SSE2 _), _ -> false
end
