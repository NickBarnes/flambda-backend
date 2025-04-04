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

(* Selection of pseudo-instructions, assignment of pseudo-registers,
   sequentialization. *)

[@@@ocaml.warning "+a-4-9-40-41-42"]

class virtual selector_generic :
  object
    method is_store : Operation.t -> bool

    method lift_op : Operation.t -> Cfg.basic

    method make_store :
      Cmm.memory_chunk -> Arch.addressing_mode -> bool -> Cfg.basic

    method make_stack_offset : int -> Cfg.basic

    method make_name_for_debugger :
      ident:Backend_var.t ->
      which_parameter:int option ->
      provenance:Backend_var.Provenance.t option ->
      is_assignment:bool ->
      regs:Reg.t array ->
      Cfg.basic

    method make_const_int : nativeint -> Operation.t

    method make_const_float32 : int32 -> Operation.t

    method make_const_float : int64 -> Operation.t

    method make_const_vec128 : Cmm.vec128_bits -> Operation.t

    method make_const_symbol : Cmm.symbol -> Operation.t

    method make_opaque : unit -> Operation.t

    (* The following methods must or can be overridden by the processor
       description *)
    method is_immediate : Simple_operation.integer_operation -> int -> bool
    (* Must be overriden to indicate whether a constant is a suitable immediate
       operand to the given integer arithmetic instruction. The default
       implementation handles shifts by immediate amounts, but produces no
       immediate operations otherwise. *)

    method virtual is_immediate_test :
      Simple_operation.integer_comparison -> int -> bool
    (* Must be defined to indicate whether a constant is a suitable immediate
       operand to the given integer test *)

    method virtual select_addressing :
      Cmm.memory_chunk ->
      Cmm.expression ->
      Arch.addressing_mode * Cmm.expression
    (* Must be defined to select addressing modes *)

    method is_simple_expr : Cmm.expression -> bool

    method effects_of : Cmm.expression -> Select_utils.Effect_and_coeffect.t
    (* Can be overridden to reflect special extcalls known to be pure *)

    method select_operation :
      Cmm.operation ->
      Cmm.expression list ->
      Debuginfo.t ->
      label_after:Label.t ->
      Cfg.basic_or_terminator * Cmm.expression list
    (* Can be overridden to deal with special arithmetic instructions *)

    method select_condition :
      Cmm.expression -> Simple_operation.test * Cmm.expression
    (* Can be overridden to deal with special test instructions *)

    method select_store :
      bool ->
      Arch.addressing_mode ->
      Cmm.expression ->
      Operation.t * Cmm.expression
    (* Can be overridden to deal with special store constant instructions *)

    method virtual select_store_new :
      bool ->
      Arch.addressing_mode ->
      Cmm.expression ->
      Cfg_selectgen_target_intf.select_store_result

    method virtual is_store_out_of_range :
      Cmm.memory_chunk ->
      byte_offset:int ->
      Cfg_selectgen_target_intf.is_store_out_of_range_result

    method regs_for : Cmm.machtype -> Reg.t array
    (* Return an array of fresh registers of the given type. Default
       implementation is like Reg.createv. Can be overridden if float values are
       stored as pairs of integer registers. *)

    method insert_op :
      Select_utils.environment ->
      Sub_cfg.t ->
      Operation.t ->
      Reg.t array ->
      Reg.t array ->
      Reg.t array
    (* Can be overridden to deal with 2-address instructions or instructions
       with hardwired input/output registers *)

    method insert_op_debug :
      Select_utils.environment ->
      Sub_cfg.t ->
      Operation.t ->
      Debuginfo.t ->
      Reg.t array ->
      Reg.t array ->
      Reg.t array
    (* Can be overridden to deal with 2-address instructions or instructions
       with hardwired input/output registers *)

    method insert_move_extcall_arg :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.exttype ->
      Reg.t array ->
      Reg.t array ->
      unit
    (* Can be overridden to deal with unusual unboxed calling conventions, e.g.
       on a 64-bit platform, passing unboxed 32-bit arguments in 32-bit stack
       slots. *)

    method emit_extcall_args :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.exttype list ->
      Cmm.expression list ->
      Reg.t array * int
    (* Can be overridden to deal with stack-based calling conventions *)

    method emit_stores :
      Select_utils.environment ->
      Sub_cfg.t ->
      Debuginfo.t ->
      Cmm.expression list ->
      Reg.t array ->
      unit
    (* Fill a freshly allocated block. Can be overridden for architectures that
       do not provide Arch.offset_addressing. *)

    method insert :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cfg.basic ->
      Reg.t array ->
      Reg.t array ->
      unit

    method insert_debug :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cfg.basic ->
      Debuginfo.t ->
      Reg.t array ->
      Reg.t array ->
      unit

    method insert' :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cfg.terminator ->
      Reg.t array ->
      Reg.t array ->
      unit

    method insert_debug' :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cfg.terminator ->
      Debuginfo.t ->
      Reg.t array ->
      Reg.t array ->
      unit

    method insert_move :
      Select_utils.environment -> Sub_cfg.t -> Reg.t -> Reg.t -> unit

    method insert_move_args :
      Select_utils.environment ->
      Sub_cfg.t ->
      Reg.t array ->
      Reg.t array ->
      int ->
      unit

    method insert_move_results :
      Select_utils.environment ->
      Sub_cfg.t ->
      Reg.t array ->
      Reg.t array ->
      int ->
      unit

    method insert_moves :
      Select_utils.environment ->
      Sub_cfg.t ->
      Reg.t array ->
      Reg.t array ->
      unit

    method emit_expr :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      bound_name:Backend_var.With_provenance.t option ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      bound_name:Backend_var.With_provenance.t option ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_raise :
      Select_utils.environment ->
      Sub_cfg.t ->
      Lambda.raise_kind ->
      Cmm.expression list ->
      Debuginfo.t ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_op :
      Select_utils.environment ->
      Sub_cfg.t ->
      Backend_var.With_provenance.t option ->
      Cmm.operation ->
      Cmm.expression list ->
      Debuginfo.t ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_ifthenelse :
      Select_utils.environment ->
      Sub_cfg.t ->
      Backend_var.With_provenance.t option ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_switch :
      Select_utils.environment ->
      Sub_cfg.t ->
      Backend_var.With_provenance.t option ->
      Cmm.expression ->
      int array ->
      (Cmm.expression * Debuginfo.t) array ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_catch :
      Select_utils.environment ->
      Sub_cfg.t ->
      Backend_var.With_provenance.t option ->
      Cmm.rec_flag ->
      (Lambda.static_label
      * (Backend_var.With_provenance.t * Cmm.machtype) list
      * Cmm.expression
      * Debuginfo.t
      * bool)
      list ->
      Cmm.expression ->
      Cmm.kind_for_unboxing ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_exit :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.exit_label ->
      Cmm.expression list ->
      Cmm.trap_action list ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_expr_trywith :
      Select_utils.environment ->
      Sub_cfg.t ->
      Backend_var.With_provenance.t option ->
      Cmm.expression ->
      Cmm.trywith_shared_label ->
      Backend_var.With_provenance.t ->
      extra_args:(Backend_var.With_provenance.t * Cmm.machtype) list ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      Reg.t array Select_utils.Or_never_returns.t

    method emit_tail :
      Select_utils.environment -> Sub_cfg.t -> Cmm.expression -> unit

    method emit_tail_apply :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.machtype ->
      Cmm.operation ->
      Cmm.expression list ->
      Debuginfo.t ->
      unit

    method emit_tail_ifthenelse :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      unit

    method emit_tail_switch :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      int array ->
      (Cmm.expression * Debuginfo.t) array ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      unit

    method emit_tail_catch :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.rec_flag ->
      (Lambda.static_label
      * (Backend_var.With_provenance.t * Cmm.machtype) list
      * Cmm.expression
      * Debuginfo.t
      * bool)
      list ->
      Cmm.expression ->
      Cmm.kind_for_unboxing ->
      unit

    method emit_tail_trywith :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      Cmm.trywith_shared_label ->
      Backend_var.With_provenance.t ->
      extra_args:(Backend_var.With_provenance.t * Cmm.machtype) list ->
      Cmm.expression ->
      Debuginfo.t ->
      Cmm.kind_for_unboxing ->
      unit

    method emit_return :
      Select_utils.environment ->
      Sub_cfg.t ->
      Cmm.expression ->
      Cmm.trap_action list ->
      unit

    method emit_fundecl :
      future_funcnames:Misc.Stdlib.String.Set.t ->
      Cmm.fundecl ->
      Cfg_with_layout.t
  end
