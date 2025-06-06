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

module Extra_arg = struct
  type t =
    | Already_in_scope of Simple.t
    | New_let_binding of Variable.t * Flambda_primitive.t
    | New_let_binding_with_named_args of
        Variable.t * (Simple.t list -> Flambda_primitive.t)

  let [@ocamlformat "disable"] print ppf t =
    match t with
    | Already_in_scope simple ->
      Format.fprintf ppf "@[<hov 1>(Already_in_scope@ %a)@]"
        Simple.print simple
    | New_let_binding (var, prim) ->
      Format.fprintf ppf "@[<hov 1>(New_let_binding@ %a@ %a)@]"
        Variable.print var
        Flambda_primitive.print prim
    | New_let_binding_with_named_args (var, _) ->
      Format.fprintf ppf "@[<hov 1>(New_let_binding_with_named_args@ %a@ <fun>)@]"
        Variable.print var

  module List = struct
    type nonrec t = t list

    let [@ocamlformat "disable"] print ppf t =
      Format.fprintf ppf "(%a)"
        (Format.pp_print_list ~pp_sep:Format.pp_print_space print) t
  end
end

type t =
  | Empty
  | Non_empty of
      { extra_params : Bound_parameters.t;
        extra_args : Extra_arg.t list Or_invalid.t Apply_cont_rewrite_id.Map.t
      }

let [@ocamlformat "disable"] print ppf = function
  | Empty -> Format.fprintf ppf "(empty)"
  | Non_empty { extra_params; extra_args; } ->
    Format.fprintf ppf "@[<hov 1>(\
        @[<hov 1>(extra_params@ %a)@]@ \
        @[<hov 1>(extra_args@ %a)@]\
        )@]"
      Bound_parameters.print extra_params
      (Apply_cont_rewrite_id.Map.print (Or_invalid.print Extra_arg.List.print)) extra_args

let empty = Empty

let is_empty = function
  | Empty -> true
  | Non_empty { extra_params = _; extra_args } ->
    Apply_cont_rewrite_id.Map.is_empty extra_args

let add t ~invalids ~extra_param ~extra_args =
  (* Note: there can be some overlap between the invalid ids and the keys of the
     [extra_args] map. This is notably used by the unboxing code which may
     compute some extra args and only later (when computing extra args for
     another parameter) realize that some rewrite ids are invalids, and then
     call this function with this new invalid set and the extra_args computed
     before this invalid set was known. *)
  match t with
  | Empty ->
    let extra_params = Bound_parameters.create [extra_param] in
    let valid_extra_args =
      Apply_cont_rewrite_id.Map.map
        (fun extra_args -> Or_invalid.Ok [extra_args])
        extra_args
    in
    let extra_args =
      Apply_cont_rewrite_id.Set.fold
        (fun id map -> Apply_cont_rewrite_id.Map.add id Or_invalid.Invalid map)
        invalids valid_extra_args
    in
    Non_empty { extra_params; extra_args }
  | Non_empty { extra_params; extra_args = already_extra_args } ->
    let extra_params = Bound_parameters.cons extra_param extra_params in
    let extra_args =
      Apply_cont_rewrite_id.Map.merge
        (fun id already_extra_args extra_arg ->
          (* The [invalids] set is expected to be small (actually, empty most of
             the time), so the lookups in each case of the merge should be
             reasonable, compared to merging (and allocating) the [invalids] set
             and the [extra_args] map. *)
          match already_extra_args, extra_arg with
          | None, None -> None
          | None, Some _ ->
            Misc.fatal_errorf
              "[Extra Params and Args] Unexpected New Apply_cont_rewrite_id \
               (%a) for:\n\
               new param: %a\n\
               new args: %a\n\
               new invalids: %a\n\
               existing epa: %a" Apply_cont_rewrite_id.print id
              Bound_parameter.print extra_param
              (Apply_cont_rewrite_id.Map.print Extra_arg.print)
              extra_args Apply_cont_rewrite_id.Set.print invalids print t
          | Some _, None ->
            if Apply_cont_rewrite_id.Set.mem id invalids
            then Some Or_invalid.Invalid
            else
              Misc.fatal_errorf
                "[Extra Params and Args] Existing Apply_cont_rewrite_id (%a) \
                 missing for:\n\
                 new param: %a\n\
                 new args: %a\n\
                 new invalids: %a\n\
                 existing epa: %a" Apply_cont_rewrite_id.print id
                Bound_parameter.print extra_param
                (Apply_cont_rewrite_id.Map.print Extra_arg.print)
                extra_args Apply_cont_rewrite_id.Set.print invalids print t
          | Some Or_invalid.Invalid, Some _ -> Some Or_invalid.Invalid
          | Some (Or_invalid.Ok already_extra_args), Some extra_arg ->
            if Apply_cont_rewrite_id.Set.mem id invalids
            then Some Or_invalid.Invalid
            else Some (Or_invalid.Ok (extra_arg :: already_extra_args)))
        already_extra_args extra_args
    in
    Non_empty { extra_params; extra_args }

let replace_extra_args t extra_args =
  match t with
  | Empty -> Empty
  | Non_empty { extra_params; _ } -> Non_empty { extra_params; extra_args }

let concat ~outer ~inner =
  match outer, inner with
  | Empty, t | t, Empty -> t
  | Non_empty t1, Non_empty t2 ->
    let extra_args =
      Apply_cont_rewrite_id.Map.merge
        (fun id extra_args1 extra_args2 ->
          match extra_args1, extra_args2 with
          | None, None -> None
          | Some _, None | None, Some _ ->
            Misc.fatal_errorf
              "concat: mismatching domains on id %a.@\nouter: %a@\ninner: %a"
              Apply_cont_rewrite_id.print id print outer print inner
          | Some Or_invalid.Invalid, Some _ | Some _, Some Or_invalid.Invalid ->
            Some Or_invalid.Invalid
          | Some (Or_invalid.Ok extra_args1), Some (Or_invalid.Ok extra_args2)
            ->
            Some (Or_invalid.Ok (extra_args1 @ extra_args2)))
        t1.extra_args t2.extra_args
    in
    Non_empty
      { extra_params = Bound_parameters.append t1.extra_params t2.extra_params;
        extra_args
      }

let extra_params = function
  | Empty -> Bound_parameters.empty
  | Non_empty { extra_params; _ } -> extra_params

let extra_args = function
  | Empty -> Apply_cont_rewrite_id.Map.empty
  | Non_empty { extra_args; _ } -> extra_args

let init_with_params_only extra_params =
  Non_empty { extra_params; extra_args = Apply_cont_rewrite_id.Map.empty }

let add_args_for_all_params t apply_cont_rewrite_id new_args =
  let error () =
    Misc.fatal_errorf "Mismatched number of extra params and extra args"
  in
  match t with
  | Empty -> ( match new_args with [] -> t | _ :: _ -> error ())
  | Non_empty { extra_params; extra_args } ->
    if not
         (List.compare_lengths new_args (Bound_parameters.to_list extra_params)
         = 0)
    then error ()
    else
      let extra_args =
        Apply_cont_rewrite_id.Map.add apply_cont_rewrite_id
          (Or_invalid.Ok new_args) extra_args
      in
      Non_empty { extra_params; extra_args }
