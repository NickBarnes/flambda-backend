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

(* Elimination of useless Llet(Alias) bindings.
   Also transform let-bound references into variables. *)

open Lambda
open Debuginfo.Scoped_location

(* To transform let-bound references into variables *)

exception Real_reference

let check_function_escape id lfun =
  (* Check that the identifier is not one of the parameters *)
  let param_is_id { name; _ } = Ident.same id name in
  assert (not (List.exists param_is_id lfun.params));
  if Ident.Set.mem id (Lambda.free_variables lfun.body) then
    raise Real_reference

let rec eliminate_ref id = function
    Lvar v as lam ->
      if Ident.same v id then raise Real_reference else lam
  | Lmutvar _ | Lconst _ as lam -> lam
  | Lapply ap ->
      Lapply{ap with ap_func = eliminate_ref id ap.ap_func;
                     ap_args = List.map (eliminate_ref id) ap.ap_args}
  | Lfunction lfun as lam ->
      check_function_escape id lfun;
      lam
  | Llet(str, kind, v, duid, e1, e2) ->
      Llet(str, kind, v, duid, eliminate_ref id e1, eliminate_ref id e2)
  | Lmutlet(kind, v, duid, e1, e2) ->
      Lmutlet(kind, v, duid, eliminate_ref id e1, eliminate_ref id e2)
  | Lletrec(idel, e2) ->
      List.iter (fun rb -> check_function_escape id rb.def) idel;
      Lletrec(idel, eliminate_ref id e2)
  | Lprim(Pfield (0, _, _), [Lvar v], _) when Ident.same v id ->
      Lmutvar id
  | Lprim(Psetfield(0, _, _), [Lvar v; e], _) when Ident.same v id ->
      Lassign(id, eliminate_ref id e)
  | Lprim(Poffsetref delta, [Lvar v], loc) when Ident.same v id ->
      Lassign(id, Lprim(Poffsetint delta, [Lmutvar id], loc))
  | Lprim(p, el, loc) ->
      Lprim(p, List.map (eliminate_ref id) el, loc)
  | Lswitch(e, sw, loc, kind) ->
      Lswitch(eliminate_ref id e,
        {sw_numconsts = sw.sw_numconsts;
         sw_consts =
            List.map (fun (n, e) -> (n, eliminate_ref id e)) sw.sw_consts;
         sw_numblocks = sw.sw_numblocks;
         sw_blocks =
            List.map (fun (n, e) -> (n, eliminate_ref id e)) sw.sw_blocks;
         sw_failaction =
            Option.map (eliminate_ref id) sw.sw_failaction; },
         loc,
         kind)
  | Lstringswitch(e, sw, default, loc, kind) ->
      Lstringswitch
        (eliminate_ref id e,
         List.map (fun (s, e) -> (s, eliminate_ref id e)) sw,
         Option.map (eliminate_ref id) default, loc, kind)
  | Lstaticraise (i,args) ->
      Lstaticraise (i,List.map (eliminate_ref id) args)
  | Lstaticcatch(e1, i, e2, r, kind) ->
      Lstaticcatch(eliminate_ref id e1, i, eliminate_ref id e2, r, kind)
  | Ltrywith(e1, v, duid, e2, kind) ->
      Ltrywith(eliminate_ref id e1, v, duid, eliminate_ref id e2, kind)
  | Lifthenelse(e1, e2, e3, kind) ->
      Lifthenelse(eliminate_ref id e1,
                  eliminate_ref id e2,
                  eliminate_ref id e3, kind)
  | Lsequence(e1, e2) ->
      Lsequence(eliminate_ref id e1, eliminate_ref id e2)
  | Lwhile lw ->
      Lwhile { wh_cond = eliminate_ref id lw.wh_cond;
               wh_body = eliminate_ref id lw.wh_body}
  | Lfor lf ->
      Lfor {lf with for_from = eliminate_ref id lf.for_from;
                    for_to = eliminate_ref id lf.for_to;
                    for_body = eliminate_ref id lf.for_body }
  | Lassign(v, e) ->
      Lassign(v, eliminate_ref id e)
  | Lsend(k, m, o, el, pos, mode, loc, layout) ->
      Lsend(k, eliminate_ref id m, eliminate_ref id o,
            List.map (eliminate_ref id) el, pos, mode, loc, layout)
  | Levent(l, ev) ->
      Levent(eliminate_ref id l, ev)
  | Lifused(v, e) ->
      Lifused(v, eliminate_ref id e)
  | Lregion (e, layout) ->
      Lregion(eliminate_ref id e, layout)
  | Lexclave e ->
      Lexclave(eliminate_ref id e)

(* Simplification of exits *)

type exit = {
  mutable count: int;
  mutable max_depth: int;
}

let simplify_exits lam =

  (* Count occurrences of (exit n ...) statements *)
  let exits = Hashtbl.create 17 in

  let get_exit i =
    try Hashtbl.find exits i
    with Not_found -> {count = 0; max_depth = 0}

  and incr_exit i nb d =
    match Hashtbl.find_opt exits i with
    | Some r ->
        r.count <- r.count + nb;
        r.max_depth <- Misc.Stdlib.Int.max r.max_depth d
    | None ->
        let r = {count = nb; max_depth = d} in
        Hashtbl.add exits i r
  in

  let rec count ~try_depth = function
  | (Lvar _| Lmutvar _ | Lconst _) -> ()
  | Lapply ap ->
      count ~try_depth ap.ap_func;
      List.iter (count ~try_depth) ap.ap_args
  | Lfunction {body} -> count ~try_depth body
  | Llet(_, _kind, _v, _duid, l1, l2)
  | Lmutlet(_kind, _v, _duid, l1, l2) ->
      count ~try_depth l2; count ~try_depth l1
  | Lletrec(bindings, body) ->
      List.iter (fun { def = { body } } -> count ~try_depth body) bindings;
      count ~try_depth body
  | Lprim(_p, ll, _) -> List.iter (count ~try_depth) ll
  | Lswitch(l, sw, _loc, _kind) ->
      count_default ~try_depth sw ;
      count ~try_depth l;
      List.iter (fun (_, l) -> count ~try_depth l) sw.sw_consts;
      List.iter (fun (_, l) -> count ~try_depth l) sw.sw_blocks
  | Lstringswitch(l, sw, d, _, _kind) ->
      count ~try_depth l;
      List.iter (fun (_, l) -> count ~try_depth l) sw;
      begin match  d with
      | None -> ()
      | Some d -> match sw with
        | []|[_] -> count ~try_depth d
        | _ -> (* default will get replicated *)
            count ~try_depth d; count ~try_depth d
      end
  | Lstaticraise (i,ls) ->
      incr_exit i 1 try_depth;
      List.iter (count ~try_depth) ls
  | Lstaticcatch (l1,(i,[]),Lstaticraise (j,[]), _, _) ->
      (* i will be replaced by j in l1, so each occurrence of i in l1
         increases j's ref count *)
      count ~try_depth l1 ;
      let ic = get_exit i in
      incr_exit j ic.count (Misc.Stdlib.Int.max try_depth ic.max_depth)
  | Lstaticcatch(l1, (i,_), l2, r, _) ->
      count ~try_depth l1;
      (* If l1 does not contain (exit i),
         l2 will be removed, so don't count its exits *)
      if (get_exit i).count > 0 then begin
        let try_depth =
          match r with
          | Popped_region -> try_depth - 1
          | Same_region -> try_depth
        in
        count ~try_depth l2
      end
  | Ltrywith(l1, _v, _duid, l2, _kind) ->
      count ~try_depth:(try_depth+1) l1;
      count ~try_depth l2;
  | Lifthenelse(l1, l2, l3, _kind) ->
      count ~try_depth l1;
      count ~try_depth l2;
      count ~try_depth l3
  | Lsequence(l1, l2) -> count ~try_depth l1; count ~try_depth l2
  | Lwhile lw -> count ~try_depth lw.wh_cond; count ~try_depth lw.wh_body
  | Lfor lf ->
      count ~try_depth lf.for_from;
      count ~try_depth lf.for_to;
      count ~try_depth lf.for_body
  | Lassign(_v, l) -> count ~try_depth l
  | Lsend(_k, m, o, ll, _, _, _, _) -> List.iter (count ~try_depth) (m::o::ll)
  | Levent(l, _) -> count ~try_depth l
  | Lifused(_v, l) -> count ~try_depth l
  | Lregion (l, _) -> count ~try_depth:(try_depth+1) l
  | Lexclave l -> count ~try_depth:(try_depth-1) l

  and count_default ~try_depth sw = match sw.sw_failaction with
  | None -> ()
  | Some al ->
      let nconsts = List.length sw.sw_consts
      and nblocks = List.length sw.sw_blocks in
      if
        nconsts < sw.sw_numconsts && nblocks < sw.sw_numblocks
      then begin (* default action will occur twice in native code *)
        count ~try_depth al ; count ~try_depth al
      end else begin (* default action will occur once *)
        assert (nconsts < sw.sw_numconsts || nblocks < sw.sw_numblocks) ;
        count ~try_depth al
      end
  in
  count ~try_depth:0 lam;

  (*
     Second pass simplify  ``catch body with (i ...) handler''
      - if (exit i ...) does not occur in body, suppress catch
      - if (exit i ...) occurs exactly once in body,
        substitute it with handler
      - If handler is a single variable, replace (exit i ..) with it
   Note:
    In ``catch body with (i x1 .. xn) handler''
     Substituted expression is
      let y1 = x1 and ... yn = xn in
      handler[x1 <- y1 ; ... ; xn <- yn]
     For the sake of preserving the uniqueness  of bound variables.
     (No alpha conversion of ``handler'' is presently needed, since
     substitution of several ``(exit i ...)''
     occurs only when ``handler'' is a variable.)
  *)

  let subst = Hashtbl.create 17 in
  let rec simplif ~layout ~try_depth l =
    (* layout is the expected layout of the result: [None] if we want to
       leave it unchanged, [Some layout] if we need to update the layout of
       the result to [layout]. *)
    let result_layout ly = Option.value layout ~default:ly in
    match l with
  | Lvar _| Lmutvar _ | Lconst _ -> l
  | Lapply ap ->
      Lapply{ap with ap_func = simplif ~layout:None ~try_depth ap.ap_func;
                     ap_args = List.map (simplif ~layout:None ~try_depth) ap.ap_args}
  | Lfunction lfun ->
      Lfunction (map_lfunction (simplif ~layout:None ~try_depth) lfun)
  | Llet(str, kind, v, duid, l1, l2) ->
      Llet(str, kind, v, duid, simplif ~layout:None ~try_depth l1,
           simplif ~layout ~try_depth l2)
  | Lmutlet(kind, v, duid, l1, l2) ->
      Lmutlet(kind, v, duid, simplif ~layout:None ~try_depth l1,
              simplif ~layout ~try_depth l2)
  | Lletrec(bindings, body) ->
      let bindings =
        List.map (fun ({ def = {kind; params; return; body = l; attr; loc;
                                mode; ret_mode } }
                       as rb) ->
                   let def =
                     lfunction' ~kind ~params ~return ~mode ~ret_mode
                       ~body:(simplif ~layout:None ~try_depth l) ~attr ~loc
                   in
                   { rb with def })
          bindings
      in
      Lletrec(bindings, simplif ~layout ~try_depth body)
  | Lprim(p, ll, loc) -> begin
    let ll = List.map (simplif ~layout:None ~try_depth) ll in
    match p, ll with
        (* Simplify Obj.with_tag *)
      | Pccall { Primitive.prim_name = "caml_obj_with_tag"; _ },
        [Lconst (Const_base (Const_int tag));
         Lprim (Pmakeblock (_, mut, shape, mode), fields, loc)] ->
         Lprim (Pmakeblock(tag, mut, shape, mode), fields, loc)
      | Pccall { Primitive.prim_name = "caml_obj_with_tag"; _ },
        [Lconst (Const_base (Const_int tag));
         Lconst (Const_block (_, fields))] ->
         Lconst (Const_block (tag, fields))

      | _ -> Lprim(p, ll, loc)
     end
  | Lswitch(l, sw, loc, kind) ->
      let new_l = simplif ~layout:None ~try_depth l
      and new_consts =
      List.map (fun (n, e) -> (n, simplif ~layout ~try_depth e)) sw.sw_consts
      and new_blocks =
      List.map (fun (n, e) -> (n, simplif ~layout ~try_depth e)) sw.sw_blocks
      and new_fail = Option.map (simplif ~layout ~try_depth) sw.sw_failaction in
      Lswitch
        (new_l,
         {sw with sw_consts = new_consts ; sw_blocks = new_blocks;
                  sw_failaction = new_fail},
         loc, result_layout kind)
  | Lstringswitch(l,sw,d,loc, kind) ->
      Lstringswitch
        (simplif ~layout:None ~try_depth l,
         List.map (fun (s,l) -> s,simplif ~layout ~try_depth l) sw,
         Option.map (simplif ~layout ~try_depth) d,
         loc,
         result_layout kind)
  | Lstaticraise (i,[]) as l ->
      begin try
        let _,handler =  Hashtbl.find subst i in
        handler
      with
      | Not_found -> l
      end
  | Lstaticraise (i,ls) ->
      let ls = List.map (simplif ~layout:None ~try_depth) ls in
      begin try
        let xs,handler =  Hashtbl.find subst i in
        let ys = List.map (fun (x, duid, k) -> Ident.rename x, duid, k) xs in
        let env =
          List.fold_right2
            (fun (x, _, _) (y, _, _) env -> Ident.Map.add x y env)
            xs ys Ident.Map.empty
        in
        (* The evaluation order for Lstaticraise arguments is currently
           right-to-left in all backends.
           To preserve this, we use fold_left2 instead of fold_right2
           (the first argument is inserted deepest in the expression,
           so will be evaluated last).
        *)
        List.fold_left2
          (fun r (y, duid, kind) l -> Llet (Strict, kind, y, duid, l, r))
          (Lambda.rename env handler) ys ls
      with
      | Not_found -> Lstaticraise (i,ls)
      end
  | Lstaticcatch (l1,(i,[]),(Lstaticraise (_j,[]) as l2),_,_) ->
      Hashtbl.add subst i ([],simplif ~layout ~try_depth l2) ;
      simplif ~layout ~try_depth l1
  | Lstaticcatch (l1,(i,xs),l2,r,kind) ->
      let try_depth =
        match r with
        | Popped_region -> try_depth - 1
        | Same_region -> try_depth
      in
      let {count; max_depth} = get_exit i in
      if count = 0 then
        (* Discard staticcatch: not matching exit *)
        simplif ~layout ~try_depth l1
      else if
      count = 1 && max_depth <= try_depth then begin
        (* Inline handler if there is a single occurrence and it is not
           nested within an inner try..with *)
        assert(max_depth = try_depth);
        Hashtbl.add subst i (xs,simplif ~layout ~try_depth l2);
        simplif ~layout:(Some (result_layout kind)) ~try_depth l1
      end else
        Lstaticcatch (
          simplif ~layout ~try_depth l1,
          (i,xs),
          simplif ~layout ~try_depth l2,
          r,
          result_layout kind)
  | Ltrywith(l1, v, duid, l2, kind) ->
      let l1 = simplif ~layout ~try_depth:(try_depth + 1) l1 in
      Ltrywith(l1, v, duid, simplif ~layout ~try_depth l2, result_layout kind)
  | Lifthenelse(l1, l2, l3, kind) ->
      Lifthenelse(
        simplif ~layout:None ~try_depth l1,
        simplif ~layout ~try_depth l2,
        simplif ~layout ~try_depth l3,
        result_layout kind)
  | Lsequence(l1, l2) ->
      Lsequence(
        simplif ~layout:None ~try_depth l1,
        simplif ~layout ~try_depth l2)
  | Lwhile lw -> Lwhile {
      wh_cond = simplif ~layout:None ~try_depth lw.wh_cond;
      wh_body = simplif ~layout:None ~try_depth lw.wh_body}
  | Lfor lf ->
      Lfor {lf with for_from = simplif ~layout:None ~try_depth lf.for_from;
                    for_to = simplif ~layout:None ~try_depth lf.for_to;
                    for_body = simplif ~layout:None ~try_depth lf.for_body}
  | Lassign(v, l) -> Lassign(v, simplif ~layout:None ~try_depth l)
  | Lsend(k, m, o, ll, pos, mode, loc, layout) ->
      Lsend(k, simplif ~layout:None ~try_depth m, simplif ~layout:None ~try_depth o,
            List.map (simplif ~layout:None ~try_depth) ll, pos, mode, loc, layout)
  | Levent(l, ev) -> Levent(simplif ~layout ~try_depth l, ev)
  | Lifused(v, l) -> Lifused (v,simplif ~layout ~try_depth l)
  | Lregion (l, ly) -> Lregion (
      simplif ~layout ~try_depth:(try_depth + 1) l,
      result_layout ly)
  | Lexclave l -> Lexclave (simplif ~layout ~try_depth:(try_depth - 1) l)
  in
  simplif ~layout:None ~try_depth:0 lam

(* Compile-time beta-reduction of functions immediately applied:
      Lapply(Lfunction(Curried, params, body), args, loc) ->
        let paramN = argN in ... let param1 = arg1 in body
      Lapply(Lfunction(Tupled, params, body), [Lprim(Pmakeblock(args))], loc) ->
        let paramN = argN in ... let param1 = arg1 in body
   Assumes |args| = |params|.
*)

let exact_application {kind; params; _} args =
  let arity = List.length params in
  Lambda.find_exact_application kind ~arity args

let beta_reduce params body args =
  List.fold_left2
    (fun l (param: lparam) arg ->
      Llet(Strict, param.layout, param.name, param.debug_uid, arg, l))
    body params args

(* Simplification of lets *)

let simplify_lets lam =

  (* Disable optimisations for bytecode compilation with -g flag *)
  let optimize = !Clflags.native_code || not !Clflags.debug in

  (* First pass: count the occurrences of all let-bound identifiers *)

  let occ = (Hashtbl.create 83: (Ident.t, int ref) Hashtbl.t) in
  (* The global table [occ] associates to each let-bound identifier
     the number of its uses (as a reference):
     - 0 if never used
     - 1 if used exactly once in and not under a lambda or within a loop
     - > 1 if used several times or under a lambda or within a loop.
     The local table [bv] associates to each locally-let-bound variable
     its reference count, as above.  [bv] is enriched at let bindings
     but emptied when crossing lambdas and loops. *)

  (* Current use count of a variable. *)
  let count_var v =
    try
      !(Hashtbl.find occ v)
    with Not_found ->
      0

  (* Entering a [let].  Returns updated [bv]. *)
  and bind_var bv v =
    let r = ref 0 in
    Hashtbl.add occ v r;
    Ident.Map.add v r bv

  (* Record a use of a variable *)
  and use_var bv v n =
    try
      let r = Ident.Map.find v bv in r := !r + n
    with Not_found ->
      (* v is not locally bound, therefore this is a use under a lambda
         or within a loop.  Increase use count by 2 -- enough so
         that single-use optimizations will not apply. *)
    try
      let r = Hashtbl.find occ v in r := !r + 2
    with Not_found ->
      (* Not a let-bound variable, ignore *)
      () in

  let rec count bv = function
  | Lconst _ -> ()
  | Lvar v ->
     use_var bv v 1
  | Lmutvar _ -> ()
  | Lapply{ap_func = ll; ap_args = args} ->
      let no_opt () = count bv ll; List.iter (count bv) args in
      begin match ll with
      | Lfunction lf when optimize ->
          begin match exact_application lf args with
          | None -> no_opt ()
          | Some exact_args ->
              count bv (beta_reduce lf.params lf.body exact_args)
          end
      | _ -> no_opt ()
      end
  | Lfunction fn ->
      count_lfunction fn
  | Llet(_str, _k, v, _duid, Lvar w, l2) when optimize ->
      (* v will be replaced by w in l2, so each occurrence of v in l2
         increases w's refcount *)
      count (bind_var bv v) l2;
      use_var bv w (count_var v)
  | Llet(str, _kind, v, _duid, l1, l2) ->
      count (bind_var bv v) l2;
      (* If v is unused, l1 will be removed, so don't count its variables *)
      if str = Strict || count_var v > 0 then count bv l1
  | Lmutlet(_kind, _v, _duid, l1, l2) ->
     count bv l1;
     count bv l2
  | Lletrec(bindings, body) ->
      List.iter (fun { def } -> count_lfunction def) bindings;
      count bv body
  | Lprim(_p, ll, _) -> List.iter (count bv) ll
  | Lswitch(l, sw, _loc, _kind) ->
      count_default bv sw ;
      count bv l;
      List.iter (fun (_, l) -> count bv l) sw.sw_consts;
      List.iter (fun (_, l) -> count bv l) sw.sw_blocks
  | Lstringswitch(l, sw, d, _, _kind) ->
      count bv l ;
      List.iter (fun (_, l) -> count bv l) sw ;
      begin match d with
      | Some d ->
          begin match sw with
          | []|[_] -> count bv d
          | _ -> count bv d ; count bv d
          end
      | None -> ()
      end
  | Lstaticraise (_i,ls) -> List.iter (count bv) ls
  | Lstaticcatch(l1, _, l2, Same_region, _) -> count bv l1; count bv l2
  | Ltrywith(l1, _v, _duid, l2, _kind) -> count bv l1; count bv l2
  | Lifthenelse(l1, l2, l3, _kind) -> count bv l1; count bv l2; count bv l3
  | Lsequence(l1, l2) -> count bv l1; count bv l2
  | Lwhile {wh_cond; wh_body} ->
      count Ident.Map.empty wh_cond; count Ident.Map.empty wh_body
  | Lfor {for_from; for_to; for_body} ->
      count bv for_from; count bv for_to; count Ident.Map.empty for_body
  | Lassign(_v, l) ->
      (* Lalias-bound variables are never assigned, so don't increase
         v's refcount *)
      count bv l
  | Lsend(_, m, o, ll, _, _, _, _) -> List.iter (count bv) (m::o::ll)
  | Levent(l, _) -> count bv l
  | Lifused(v, l) ->
      if count_var v > 0 then count bv l
  | Lregion (l, _) ->
      count bv l
  | Lexclave l ->
      (* Not safe in general to move code into an exclave, so block
         single-use optimizations by treating them the same as lambdas
         and loops *)
      count Ident.Map.empty l
  | Lstaticcatch(l1, _, l2, Popped_region, _) ->
      count bv l1;
      (* Don't move code into an exclave *)
      count Ident.Map.empty l2

  and count_lfunction fn =
    count Ident.Map.empty fn.body

  and count_default bv sw = match sw.sw_failaction with
  | None -> ()
  | Some al ->
      let nconsts = List.length sw.sw_consts
      and nblocks = List.length sw.sw_blocks in
      if
        nconsts < sw.sw_numconsts && nblocks < sw.sw_numblocks
      then begin (* default action will occur twice in native code *)
        count bv al ; count bv al
      end else begin (* default action will occur once *)
        assert (nconsts < sw.sw_numconsts || nblocks < sw.sw_numblocks) ;
        count bv al
      end
  in
  count Ident.Map.empty lam;

  (* Second pass: remove Lalias bindings of unused variables,
     and substitute the bindings of variables used exactly once. *)

  let subst = Hashtbl.create 83 in

(* This (small)  optimisation is always legal, it may uncover some
   tail call later on. *)

  let mklet str kind v duid e1 e2 =
    match e2 with
    | Lvar w when optimize && Ident.same v w -> e1
    | _ -> Llet (str, kind,v,duid,e1,e2)
  in

  let mkmutlet kind v duid e1 e2 =
    match e2 with
    | Lmutvar w when optimize && Ident.same v w -> e1
    | _ -> Lmutlet (kind,v,duid,e1,e2)
  in

  let rec simplif = function
    Lvar v as l ->
      begin try
        Hashtbl.find subst v
      with Not_found ->
        l
      end
  | Lmutvar _ | Lconst _ as l -> l
  | Lapply ({ap_func = ll; ap_args = args} as ap) ->
      let no_opt () =
        Lapply {ap with ap_func = simplif ap.ap_func;
                        ap_args = List.map simplif ap.ap_args} in
      begin match ll with
      | Lfunction lf when optimize ->
          begin match exact_application lf args with
          | None -> no_opt ()
          | Some exact_args ->
              simplif (beta_reduce lf.params lf.body exact_args)
          end
      | _ -> no_opt ()
      end
  | Lfunction{kind=outer_kind; params; return=outer_return; body = l;
              attr=attr1; loc; ret_mode; mode} ->
      begin match outer_kind, ret_mode, simplif l with
        Curried {nlocal=0},
        Alloc_heap,
        Lfunction{kind=Curried _ as kind; params=params'; return=return2;
                  body; attr=attr2; loc; mode=inner_mode; ret_mode}
        when optimize &&
             attr1.may_fuse_arity && attr2.may_fuse_arity &&
             List.length params + List.length params' <= Lambda.max_arity() ->
          (* The returned function's mode should match the outer return mode *)
          assert (is_heap_mode inner_mode);
          (* The return type is the type of the value returned after
             applying all the parameters to the function. The return
             type of the merged function taking [params @ params'] as
             parameters is the type returned after applying [params']. *)
          let return = return2 in
          lfunction ~kind ~params:(params @ params') ~return ~body ~attr:attr1 ~loc ~mode ~ret_mode
      | kind, ret_mode, body ->
          lfunction ~kind ~params ~return:outer_return ~body ~attr:attr1 ~loc ~mode ~ret_mode
      end
  | Llet(_str, _k, v, _duid, Lvar w, l2) when optimize ->
      Hashtbl.add subst v (simplif (Lvar w));
      simplif l2
  | Llet(Strict, kind, v, duid,
         Lprim(Pmakeblock(0, Mutable, kind_ref, _mode) as prim, [linit], loc),
         lbody)
    when optimize ->
      let slinit = simplif linit in
      let slbody = simplif lbody in
      begin try
        let kind = match kind_ref with
          | None ->
              (* This is a [Pmakeblock] so the fields are all values *)
              Lambda.layout_value_field
          | Some [field_kind] -> Pvalue field_kind
          | Some _ -> assert false
        in
        mkmutlet kind v duid slinit (eliminate_ref v slbody)
      with Real_reference ->
        mklet Strict kind v duid (Lprim(prim, [slinit], loc)) slbody
      end
  | Llet(Alias, kind, v, duid, l1, l2) ->
      begin match count_var v with
        0 -> simplif l2
      | 1 when optimize -> Hashtbl.add subst v (simplif l1); simplif l2
      | _ -> Llet(Alias, kind, v, duid, simplif l1, simplif l2)
      end
  | Llet(StrictOpt, kind, v, duid, l1, l2) ->
      begin match count_var v with
        0 -> simplif l2
      | _ -> mklet StrictOpt kind v duid (simplif l1) (simplif l2)
      end
  | Llet(str, kind, v, duid, l1, l2) ->
    mklet str kind v duid (simplif l1) (simplif l2)
  | Lmutlet(kind, v, duid, l1, l2) ->
    mkmutlet kind v duid (simplif l1) (simplif l2)
  | Lletrec(bindings, body) ->
      let bindings =
        List.map (fun rb ->
            { rb with def = map_lfunction simplif rb.def }
          ) bindings
      in
      Lletrec(bindings, simplif body)
  | Lprim(p, ll, loc) -> Lprim(p, List.map simplif ll, loc)
  | Lswitch(l, sw, loc, kind) ->
      let new_l = simplif l
      and new_consts =  List.map (fun (n, e) -> (n, simplif e)) sw.sw_consts
      and new_blocks =  List.map (fun (n, e) -> (n, simplif e)) sw.sw_blocks
      and new_fail = Option.map simplif sw.sw_failaction in
      Lswitch
        (new_l,
         {sw with sw_consts = new_consts ; sw_blocks = new_blocks;
                  sw_failaction = new_fail},
         loc, kind)
  | Lstringswitch (l,sw,d,loc, kind) ->
      Lstringswitch
        (simplif l,List.map (fun (s,l) -> s,simplif l) sw,
         Option.map simplif d,loc, kind)
  | Lstaticraise (i,ls) ->
      Lstaticraise (i, List.map simplif ls)
  | Lstaticcatch(l1, (i,args), l2, r, kind) ->
      Lstaticcatch (simplif l1, (i,args), simplif l2, r, kind)
  | Ltrywith(l1, v, duid, l2, kind) ->
    Ltrywith(simplif l1, v, duid, simplif l2, kind)
  | Lifthenelse(l1, l2, l3, kind) -> Lifthenelse(simplif l1, simplif l2, simplif l3, kind)
  | Lsequence(Lifused(v, l1), l2) ->
      if count_var v > 0
      then Lsequence(simplif l1, simplif l2)
      else simplif l2
  | Lsequence(l1, l2) -> Lsequence(simplif l1, simplif l2)
  | Lwhile lw -> Lwhile { wh_cond = simplif lw.wh_cond;
                          wh_body = simplif lw.wh_body}
  | Lfor lf -> Lfor {lf with for_from = simplif lf.for_from;
                             for_to = simplif lf.for_to;
                             for_body = simplif lf.for_body}
  | Lassign(v, l) -> Lassign(v, simplif l)
  | Lsend(k, m, o, ll, pos, mode, loc, layout) ->
      Lsend(k, simplif m, simplif o, List.map simplif ll, pos, mode, loc, layout)
  | Levent(l, ev) -> Levent(simplif l, ev)
  | Lifused(v, l) ->
      if count_var v > 0 then simplif l else lambda_unit
  | Lregion (l, layout) -> Lregion (simplif l, layout)
  | Lexclave l -> Lexclave (simplif l)
  in
  simplif lam

(* Tail call info in annotation files *)

let rec emit_tail_infos is_tail lambda =
  match lambda with
  | Lvar _ -> ()
  | Lmutvar _ -> ()
  | Lconst _ -> ()
  | Lapply ap ->
      begin
        (* Note: is_tail does not take backend-specific logic into
           account (maximum number of parameters, etc.)  so it may
           over-approximate tail-callness.

           Trying to do something more fine-grained would result in
           different warnings depending on whether the native or
           bytecode compiler is used. *)
        let maybe_warn ~is_tail ~expect_tail =
          if is_tail <> expect_tail then
            Location.prerr_warning (to_location ap.ap_loc)
              (Warnings.Wrong_tailcall_expectation expect_tail) in
        match ap.ap_tailcall with
        | Default_tailcall -> ()
        | Tailcall_expectation expect_tail ->
            maybe_warn ~is_tail ~expect_tail
      end;
      emit_tail_infos false ap.ap_func;
      list_emit_tail_infos false ap.ap_args
  | Lfunction lfun ->
      emit_tail_infos_lfunction is_tail lfun
  | Llet (_, _k, _, _, lam, body)
  | Lmutlet (_k, _, _, lam, body) ->
      emit_tail_infos false lam;
      emit_tail_infos is_tail body
  | Lletrec (bindings, body) ->
      List.iter (fun { def } -> emit_tail_infos_lfunction is_tail def) bindings;
      emit_tail_infos is_tail body
  | Lprim ((Pbytes_to_string | Pbytes_of_string |
            Parray_to_iarray | Parray_of_iarray),
           [arg],
           _) ->
      emit_tail_infos is_tail arg
  | Lprim (Psequand, [arg1; arg2], _)
  | Lprim (Psequor, [arg1; arg2], _) ->
      emit_tail_infos false arg1;
      emit_tail_infos is_tail arg2
  | Lprim (_, l, _) ->
      list_emit_tail_infos false l
  | Lswitch (lam, sw, _loc, _k) ->
      emit_tail_infos false lam;
      list_emit_tail_infos_fun snd is_tail sw.sw_consts;
      list_emit_tail_infos_fun snd is_tail sw.sw_blocks;
      Option.iter  (emit_tail_infos is_tail) sw.sw_failaction
  | Lstringswitch (lam, sw, d, _, _k) ->
      emit_tail_infos false lam;
      List.iter
        (fun (_,lam) ->  emit_tail_infos is_tail lam)
        sw ;
      Option.iter (emit_tail_infos is_tail) d
  | Lstaticraise (_, l) ->
      list_emit_tail_infos false l
  | Lstaticcatch (body, _, handler, _, _kind) ->
      emit_tail_infos is_tail body;
      emit_tail_infos is_tail handler
  | Ltrywith (body, _, _, handler, _k) ->
      emit_tail_infos false body;
      emit_tail_infos is_tail handler
  | Lifthenelse (cond, ifso, ifno, _k) ->
      emit_tail_infos false cond;
      emit_tail_infos is_tail ifso;
      emit_tail_infos is_tail ifno
  | Lsequence (lam1, lam2) ->
      emit_tail_infos false lam1;
      emit_tail_infos is_tail lam2
  | Lwhile lw ->
      emit_tail_infos false lw.wh_cond;
      emit_tail_infos false lw.wh_body
  | Lfor {for_from; for_to; for_body} ->
      emit_tail_infos false for_from;
      emit_tail_infos false for_to;
      emit_tail_infos false for_body
  | Lassign (_, lam) ->
      emit_tail_infos false lam
  | Lsend (_, meth, obj, args, _, _, _loc, _) ->
      emit_tail_infos false meth;
      emit_tail_infos false obj;
      list_emit_tail_infos false args
  | Levent (lam, _) ->
      emit_tail_infos is_tail lam
  | Lifused (_, lam) ->
      emit_tail_infos is_tail lam
  | Lregion (lam, _) ->
      emit_tail_infos is_tail lam
  | Lexclave lam ->
      emit_tail_infos is_tail lam
and list_emit_tail_infos_fun f is_tail =
  List.iter (fun x -> emit_tail_infos is_tail (f x))
and list_emit_tail_infos is_tail =
  List.iter (emit_tail_infos is_tail)
and emit_tail_infos_lfunction _is_tail lfun =
  (* Tail call annotations are only meaningful with respect to the
     current function; so entering a function resets the [is_tail] flag *)
  emit_tail_infos true lfun.body

(* Split a function with default parameters into a wrapper and an
   inner function.  The wrapper fills in missing optional parameters
   with their default value and tail-calls the inner function.  The
   wrapper can then hopefully be inlined on most call sites to avoid
   the overhead associated with boxing an optional argument with a
   'Some' constructor, only to deconstruct it immediately in the
   function's body. *)

let split_default_wrapper ~id:fun_id ~debug_uid:fun_duid ~kind ~params ~return
      ~body ~attr ~loc ~mode ~ret_mode =
  let rec aux map add_region = function
    (* When compiling [fun ?(x=expr) -> body], this is first translated
       to:
       [fun *opt* ->
          let x =
            match *opt* with
            | None -> expr
            | Some *sth* -> *sth*
          in
          body]
       We want to detect the let binding to put it into the wrapper instead of
       the inner function.
       We need to find which optional parameter the binding corresponds to,
       which is why we need a deep pattern matching on the expected result of
       the pattern-matching compiler for options.
    *)
    | Llet(Strict, k, id, duid,
           (Lifthenelse(Lprim (Pisint _, [Lvar optparam], _), _, _, _) as def),
           rest) when
        String.starts_with (Ident.name optparam) ~prefix:"*opt*" &&
        List.exists (fun p -> Ident.same p.name optparam) params
          && not (List.mem_assoc optparam map)
      ->
        let wrapper_body, inner = aux ((optparam, id) :: map) add_region rest in
        Llet(Strict, k, id, duid, def, wrapper_body), inner
    | Lregion (rest, ret) ->
        let wrapper_body, inner = aux map true rest in
        if may_allocate_in_region wrapper_body then
          Lregion (wrapper_body, ret), inner
        else wrapper_body, inner
    | Lexclave rest -> aux map true rest
    | _ when map = [] -> raise Exit
    | body ->
        (* Check that those *opt* identifiers don't appear in the remaining
           body. This should not appear, but let's be on the safe side. *)
        let fv = Lambda.free_variables body in
        List.iter (fun (id, _) -> if Ident.Set.mem id fv then raise Exit) map;

        let inner_id = Ident.create_local (Ident.name fun_id ^ "_inner") in
        let inner_id_duid = Lambda.debug_uid_none in
        let map_param (p : Lambda.lparam) =
          try
            {
              name = List.assoc p.name map;
              debug_uid = p.debug_uid;
              layout = Lambda.layout_optional_arg;
              attributes = Lambda.default_param_attribute;
              mode = p.mode
            }
          with
            Not_found -> p
        in
        let args = List.map (fun p -> Lvar (map_param p).name) params in
        let wrapper_body =
          Lapply {
            ap_func = Lvar inner_id;
            ap_args = args;
            ap_result_layout = return;
            ap_loc = loc;
            ap_region_close = Rc_normal;
            ap_mode = alloc_heap;
            ap_tailcall = Default_tailcall;
            ap_inlined = Default_inlined;
            ap_specialised = Default_specialise;
            ap_probe=None;
          }
        in
        let inner_params = List.map map_param params in
        let new_ids =
          List.map (fun p -> { p with name = Ident.rename p.name }) inner_params
        in
        let subst =
          List.fold_left2 (fun s p new_p ->
            Ident.Map.add p.name new_p.name s
          ) Ident.Map.empty inner_params new_ids
        in
        let body = Lambda.rename subst body in
        let body = if add_region then Lregion (body, return) else body in
        let inner_fun =
          lfunction' ~kind:(Curried {nlocal=0})
            ~params:new_ids
            ~return ~body ~attr ~loc ~mode ~ret_mode
        in
        (wrapper_body, { id = inner_id;
                         debug_uid = inner_id_duid;
                         def = inner_fun })
  in
  try
    (* TODO: enable this optimisation even in the presence of local returns *)
    begin match kind, ret_mode with
    | Curried {nlocal}, _ when nlocal > 0 -> raise Exit
    | Tupled, Alloc_local -> raise Exit
    | _, Alloc_heap -> ()
    | _, Alloc_local -> assert false
    end;
    let body, inner = aux [] false body in
    let attr = { default_stub_attribute with zero_alloc = attr.zero_alloc } in
    [{ id = fun_id;
       debug_uid = fun_duid;
       def = lfunction' ~kind ~params ~return ~body ~attr ~loc
           ~mode ~ret_mode };
     inner]
  with Exit ->
    [{ id = fun_id;
       debug_uid = fun_duid;
       def = lfunction' ~kind ~params ~return ~body ~attr ~loc
           ~mode ~ret_mode  }]

(* Simplify local let-bound functions: if all occurrences are
   fully-applied function calls in the same "tail scope", replace the
   function by a staticcatch handler (on that scope).

   This handles as a special case functions used exactly once (in any
   scope) for a full application.
*)

type slot =
  {
    func: lfunction;
    function_scope: lambda;
    mutable scope: lambda option;
    mutable closed_region: lambda option;
  }

type exclave_status =
  | No_exclave
  | Exclave
  | Within_exclave

module LamTbl = Hashtbl.Make(struct
    type t = lambda
    let equal = (==)
    let hash = Hashtbl.hash
  end)

let simplify_local_functions lam =
  let slots = Hashtbl.create 16 in
  let static_id = Hashtbl.create 16 in (* function id -> static id *)
  let static = LamTbl.create 16 in (* scope -> static function on that scope *)
  (* We keep track of the current "tail scope", identified
     by the outermost lambda for which the the current lambda
     is in tail position. *)
  let current_scope = ref lam in
  let current_region_scope = ref None in
  (* PR11383: We will only apply the transformation if we don't have to move
     code across function boundaries *)
  let current_function_scope = ref lam in
  let check_static lf =
    if lf.attr.local = Always_local then
      Location.prerr_warning (to_location lf.loc)
        (Warnings.Inlining_impossible
           "This function cannot be compiled into a static continuation")
  in
  let enabled = function
    | {local = Always_local; _}
    | {local = Default_local;
       inline = (Never_inline | Default_inline | Available_inline); _}
      -> true
    | {local = Default_local;
       inline = (Always_inline | Unroll _); _}
    | {local = Never_local; _}
      -> false
  in
  let is_current_region_scope scope =
    match !current_region_scope with
    | None -> false
    | Some sco -> sco == scope
  in
  let rec tail = function
    | Llet (_str, _kind, id, _duid, Lfunction lf, cont) when enabled lf.attr ->
        let r =
          { func = lf;
            function_scope = !current_function_scope;
            scope = None;
            closed_region = None }
        in
        Hashtbl.add slots id r;
        tail cont;
        begin match Hashtbl.find_opt slots id with
        | Some {scope = Some scope; closed_region; _} ->
            let st = next_raise_count () in
            let sc, exclave =
              (* Do not move higher than current lambda *)
              if scope == !current_scope then cont, No_exclave
              else if is_current_region_scope scope then begin
                match closed_region with
                | Some region when region == !current_scope ->
                    cont, Exclave
                | _ ->
                    cont, Within_exclave
              end else scope, No_exclave
            in
            Hashtbl.add static_id id st;
            LamTbl.add static sc (st, lf, exclave);
            (* The body of the function will become an handler
               in that "scope". *)
            with_scope ~scope lf.body
        | _ ->
            check_static lf;
            (* note: if scope = None, the function is unused *)
            function_definition lf
        end
    | Lapply {ap_func = Lvar id; ap_args; ap_region_close; _} ->
        let curr_scope, closed_region =
          match ap_region_close with
          | Rc_normal | Rc_nontail -> !current_scope, None
          | Rc_close_at_apply ->
              Option.get !current_region_scope, Some !current_scope
        in
        begin match Hashtbl.find_opt slots id with
        | Some {func; _}
          when exact_application func ap_args = None ->
            (* Wrong arity *)
            Hashtbl.remove slots id
        | Some {scope = Some scope; _} when scope != curr_scope ->
            (* Different "tail scope" *)
            Hashtbl.remove slots id
        | Some {function_scope = fscope; _}
          when fscope != !current_function_scope ->
            (* Different function *)
            Hashtbl.remove slots id
        | Some ({scope = None; _} as slot) ->
            (* First use of the function: remember the current tail scope *)
            slot.scope <- Some curr_scope;
            slot.closed_region <- closed_region
        | Some ({closed_region = Some old_closed_region} as slot) -> begin
            match closed_region with
            | Some closed_region when closed_region == old_closed_region ->
                ()
            | _ -> slot.closed_region <- None
          end
        | _ -> ()
        end;
        List.iter non_tail ap_args
    | Lvar id ->
        Hashtbl.remove slots id
    | Lfunction lf ->
        check_static lf;
        function_definition lf
    | Lregion (lam, _) -> region lam
    | Lexclave lam -> exclave lam
    | lam ->
        Lambda.shallow_iter ~tail ~non_tail lam
  and non_tail lam =
    with_scope ~scope:lam lam
  and region lam =
    let old_tail_scope = !current_region_scope in
    let old_scope = !current_scope in
    current_region_scope := Some !current_scope;
    current_scope := lam;
    tail lam;
    current_scope := old_scope;
    current_region_scope := old_tail_scope
  and exclave lam =
    let old_current_scope = !current_scope in
    let old_tail_scope = !current_region_scope in
    current_scope := Option.get !current_region_scope;
    current_region_scope := None;
    tail lam;
    current_region_scope := old_tail_scope;
    current_scope := old_current_scope
  and function_definition lf =
    let old_function_scope = !current_function_scope in
    current_function_scope := lf.body;
    non_tail lf.body;
    current_function_scope := old_function_scope
  and with_scope ~scope lam =
    let old_scope = !current_scope in
    let old_tail_scope = !current_region_scope in
    current_scope := scope;
    current_region_scope := None;
    tail lam;
    current_scope := old_scope;
    current_region_scope := old_tail_scope
  in
  tail lam;
  let rec rewrite lam0 =
    let lam =
      match lam0 with
      | Llet (_, _, id, _duid, _, cont) when Hashtbl.mem static_id id ->
          rewrite cont
      | Lapply {ap_func = Lvar id; ap_args; _} when Hashtbl.mem static_id id ->
         let st = Hashtbl.find static_id id in
         let slot = Hashtbl.find slots id in
         begin match exact_application slot.func ap_args with
           | None -> assert false
           | Some exact_args ->
              Lstaticraise (st, List.map rewrite exact_args)
         end
      | lam ->
          Lambda.shallow_map ~tail:rewrite ~non_tail:rewrite lam
    in
    let new_params lf =
      List.map
        (fun (p: lparam) -> (p.name, p.debug_uid, p.layout)) lf.params
    in
    List.fold_right
      (fun (st, lf, exclave) lam ->
         let body = rewrite lf.body in
         let body, r =
           match exclave with
           | No_exclave -> body, Same_region
           | Exclave -> Lexclave body, Same_region
           | Within_exclave -> body, Popped_region
         in
         Lstaticcatch (lam, (st, new_params lf), body, r, lf.return)
      )
      (LamTbl.find_all static lam0)
      lam
  in
  if LamTbl.length static = 0 then
    lam
  else
    rewrite lam

(* The entry point:
   simplification
   + rewriting of tail-modulo-cons calls
   + emission of tailcall annotations, if needed
*)

let simplify_lambda lam =
  let lam =
    lam
    |> (if !Clflags.native_code || not !Clflags.debug
        then simplify_local_functions else Fun.id
       )
    |> simplify_exits
    |> simplify_lets
    |> Tmc.rewrite
  in
  if !Clflags.annotations
     || Warnings.is_active (Warnings.Wrong_tailcall_expectation true)
  then emit_tail_infos true lam;
  lam
