(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                       Pierre Chambart, OCamlPro                        *)
(*           Mark Shinwell and Leo White, Jane Street Europe              *)
(*                                                                        *)
(*   Copyright 2013--2019 OCamlPro SAS                                    *)
(*   Copyright 2014--2019 Jane Street Group LLC                           *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open! Flambda

val simplify_let_cont :
  simplify_expr:Expr.t Simplify_common.expr_simplifier ->
  Let_cont.t Simplify_common.expr_simplifier

val simplify_as_recursive_let_cont :
  simplify_expr:Expr.t Simplify_common.expr_simplifier ->
  (Expr.t * Continuation_handler.t Continuation.Lmap.t)
  Simplify_common.expr_simplifier
