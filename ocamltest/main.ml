(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Sebastien Hinderer, projet Gallium, INRIA Paris            *)
(*                                                                        *)
(*   Copyright 2016 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Main program of the ocamltest test driver *)

open Ocamltest_stdlib
open Tsl_ast
open Tsl_semantics

type behavior =
  | Skip_all
  | Run

(* this primitive announce should be used for tests
   that were aborted on system error before ocamltest
   could parse them *)
let announce_test_error test_filename error =
  Printf.printf " ... testing '%s' => unexpected error (%s)\n%!"
    (Filename.basename test_filename) error

let print_exn loc e =
  let open Printf in
  let locstring =
    if loc = Location.none then "" else begin
      let file = loc.Location.loc_start.Lexing.pos_fname in
      let line = loc.Location.loc_start.Lexing.pos_lnum in
      sprintf "%s:%d: " file line
    end
  in
  let msg =
    match e with
    | Variables.Variable_already_registered v ->
      sprintf "Variable \"%s\" is already in the environment." v
    | Variables.No_such_variable v ->
      sprintf "Variable \"%s\" is not in the environment." v
    | Environments.Modifiers_name_not_found name ->
      sprintf "Environment modifier \"%s\" does not exist." name
    | Tsl_semantics.No_such_test_or_action name ->
      sprintf "This is not the name of a test or an action: \"%s\"." name
    | Ocaml_actions.Cannot_compile_file_type t ->
      sprintf "Cannot compile files of type %s." t
    | _ ->
      sprintf "Unexpected exception: %s" (Printexc.to_string e)
  in
  eprintf "\n%s%s\n%!" locstring msg

exception Syntax_error of Lexing.position

let tsl_parse_file test_filename =
  let input_channel = open_in test_filename in
  let lexbuf = Lexing.from_channel input_channel in
  Location.init lexbuf test_filename;
  match Tsl_parser.tsl_script Tsl_lexer.token lexbuf with
    | exception Parsing.Parse_error ->
      raise (Syntax_error lexbuf.Lexing.lex_start_p)
    | exception e -> close_in input_channel; raise e
    | _ as tsl_block -> close_in input_channel; tsl_block

let tsl_parse_file_safe test_filename =
  try tsl_parse_file test_filename with
  | Sys_error message ->
    Printf.eprintf "%s\n%!" message;
    announce_test_error test_filename message;
    exit 1
  | Syntax_error p ->
    let open Lexing in
    Printf.eprintf "%s:%d.%d: syntax error in test script\n%!"
      test_filename p.pos_lnum (p.pos_cnum - p.pos_bol);
    announce_test_error test_filename "could not read test script";
    exit 1

let print_usage () =
  Printf.printf "%s\n%!" Options.usage

let report_error loc e =
  print_exn loc e;
  "=> error in test script"

type result_summary = No_failure | Some_failure | All_skipped
let join_result summary result =
  let open Result in
  match result.status, summary with
  | Fail, _
  | (Pass | Skip | Predicate _), Some_failure -> Some_failure
  | (Skip | Predicate false), All_skipped -> All_skipped
  | Pass, All_skipped -> No_failure
  | Predicate true, All_skipped -> No_failure
  | (Pass | Skip | Predicate _), No_failure -> No_failure

let join_summaries sa sb =
  match sa, sb with
  | Some_failure, (No_failure | Some_failure | All_skipped)
  | (No_failure | All_skipped), Some_failure -> Some_failure
  | All_skipped, All_skipped -> All_skipped
  | No_failure, (No_failure | All_skipped)
  | All_skipped, No_failure -> No_failure

let rec run_test_tree log common_prefix behavior env summ ast
      ~must_do_something =
  match ast with
  | Ast (Environment_statement s :: stmts, subs) ->
    begin match interpret_environment_statement env s with
    | env ->
      run_test_tree log common_prefix behavior env summ (Ast (stmts, subs))
        ~must_do_something
    | exception e ->
      let line = s.loc.Location.loc_start.Lexing.pos_lnum in
      Printf.printf "%s line %d %!" common_prefix line;
      Printf.printf "%s\n%!" (report_error s.loc e);
      Some_failure
    end
  | Ast (Test (_, name, mods) :: stmts, subs) ->
    let skip_all =
      match behavior with
      | Skip_all -> true
      | Run -> false
    in
    let locstr =
      if name.loc = Location.none then
        "default"
      else
        Printf.sprintf "line %d" name.loc.Location.loc_start.Lexing.pos_lnum
    in
    if not skip_all then
      Printf.printf "%s %s (%s) %!" common_prefix locstr name.node;
    let test = lookup_test name in
    let must_do_something =
      must_do_something && not (Tests.does_something test)
    in
    let (msg, children_behavior, newenv, result) =
      match behavior with
      | Skip_all -> ("", Skip_all, env, Result.skip)
      | Run ->
        begin try
          let testenv = List.fold_left apply_modifiers env mods in
          let (result, newenv) = Tests.run log testenv test in
          let msg = Result.string_of_result result in
          let sub_behavior = if Result.is_pass result then Run else Skip_all in
          (msg, sub_behavior, newenv, result)
        with e ->
          (report_error name.loc e, Skip_all, env, Result.fail)
        end
    in
    if not skip_all then Printf.printf "%s\n%!" msg;
    let newsumm = join_result summ result in
    let newast = Ast (stmts, subs) in
    run_test_tree log common_prefix children_behavior newenv newsumm newast
      ~must_do_something
  | Ast ([], []) ->
    if not must_do_something then summ
    else (
      match summ with
      | No_failure ->
        Printf.printf "%s: does the test tree do something? => failed\n%!"
          common_prefix;
        Some_failure
      | All_skipped | Some_failure -> summ
    )
  | Ast ([], subs) ->
    (* CR mshinwell/xclerc: maybe sequences of actions that "do something" and
       then have further actions that do not "do something" should be
       flagged *)
    List.fold_left join_summaries summ
      (List.map (run_test_tree log common_prefix behavior env All_skipped
        ~must_do_something) subs)

let run_test_tree log common_prefix behavior env summ ast =
  run_test_tree log common_prefix behavior env summ ast ~must_do_something:true

let get_test_source_directory test_dirname =
  if (Filename.is_relative test_dirname) then
    Sys.with_chdir test_dirname Sys.getcwd
  else test_dirname

let get_test_build_directory_prefix test_dirname =
  let ocamltestdir_variable = "OCAMLTESTDIR" in
  let root =
    Sys.getenv_with_default_value ocamltestdir_variable
      (Filename.concat (Sys.getcwd ()) "_ocamltest")
  in
  if test_dirname = "." then root
  else Filename.concat root test_dirname

let tests_to_skip = ref []

let init_tests_to_skip () =
  tests_to_skip := String.words (Sys.safe_getenv "OCAMLTEST_SKIP_TESTS")

let extract_rootenv (Ast (stmts, subs)) =
  let (env, stmts) = split_env stmts in
  (env, Ast (stmts, subs))

let test_file test_filename =
  let start = if Options.show_timings then Unix.gettimeofday () else 0.0 in
  let skip_test = List.mem test_filename !tests_to_skip in
  let tsl_ast = tsl_parse_file_safe test_filename in
  let (rootenv_statements, tsl_ast) = extract_rootenv tsl_ast in
  let tsl_ast = match[@ocaml.warning "-fragile-match"] tsl_ast with
    | Ast ([], []) ->
      let default_tests = Tests.default_tests() in
      let make_tree test =
        let id = make_identifier test.Tests.test_name in
        Ast ([Test (0, id, [])], [])
      in
      Ast ([], List.map make_tree default_tests)
    | _ -> tsl_ast
  in
  let used_tests = tests_in_tree tsl_ast in
  let used_actions = actions_in_tests used_tests in
  let action_names =
    let f act names = String.Set.add (Actions.name act) names in
    Actions.ActionSet.fold f used_actions String.Set.empty in
  let test_dirname = Filename.dirname test_filename in
  let test_basename = Filename.basename test_filename in
  let test_prefix = Filename.chop_extension test_basename in
  let test_directory =
    if test_dirname="." then test_prefix
    else Filename.concat test_dirname test_prefix in
  let test_source_directory = get_test_source_directory test_dirname in
  let hookname_prefix = Filename.concat test_source_directory test_prefix in
  let test_build_directory_prefix =
    get_test_build_directory_prefix test_directory in
  let clean_test_build_directory () =
    try
      Sys.rm_rf test_build_directory_prefix
    with Sys_error _ -> ()
  in
  clean_test_build_directory ();
  Sys.make_directory test_build_directory_prefix;
  let log_filename =
    Filename.concat test_build_directory_prefix (test_prefix ^ ".log") in
  let log =
    if Options.log_to_stderr then stderr else begin
      open_out log_filename
    end in
  let summary = Sys.with_chdir test_build_directory_prefix
    (fun () ->
       let promote = string_of_bool Options.promote in
       let default_timeout = string_of_int Options.default_timeout in
       let install_hook name =
         let hook_name = Filename.make_filename hookname_prefix name in
         if Sys.file_exists hook_name then begin
           let hook = Actions_helpers.run_hook hook_name in
           Actions.set_hook name hook
         end in
       String.Set.iter install_hook action_names;

       let reference_filename = Filename.concat
           test_source_directory (test_prefix ^ ".reference") in
       let make = try Sys.getenv "MAKE" with Not_found -> "make" in
       let initial_environment = Environments.from_bindings
           [
             Builtin_variables.make, make;
             Builtin_variables.test_file, test_basename;
             Builtin_variables.reference, reference_filename;
             Builtin_variables.test_source_directory, test_source_directory;
             Builtin_variables.test_build_directory_prefix,
               test_build_directory_prefix;
             Builtin_variables.promote, promote;
             Builtin_variables.timeout, default_timeout;
           ] in
       let common_prefix = " ... testing '" ^ test_basename ^ "' with" in
       let initial_status = if skip_test then Skip_all else Run in
       let rootenv =
         Environments.initialize Environments.Pre log initial_environment
       in
       let rootenv, initial_status =
         let rec loop env stmts =
           match stmts with
           | [] -> (env, initial_status)
           | s :: t ->
             begin match interpret_environment_statement env s with
             | env -> loop env t
             | exception e ->
               let line = s.loc.Location.loc_start.Lexing.pos_lnum in
               Printf.printf "%s line %d %!" common_prefix line;
               Printf.printf "%s\n%!" (report_error s.loc e);
               (env, Skip_all)
             end
         in
         loop rootenv rootenv_statements
       in
       let rootenv = Environments.initialize Environments.Post log rootenv in
       let summary =
         run_test_tree log common_prefix initial_status rootenv All_skipped
           tsl_ast
       in
       Actions.clear_all_hooks();
       summary
    ) in
  if not Options.log_to_stderr then close_out log;
  begin match summary with
  | Some_failure ->
      if not Options.log_to_stderr then
        Sys.dump_file stderr ~prefix:"> " log_filename
  | No_failure | All_skipped ->
      if not Options.keep_test_dir_on_success then
        clean_test_build_directory ()
  end;
  if Options.show_timings && summary = No_failure then
    let wall_clock_duration = Unix.gettimeofday () -. start in
    Printf.eprintf "Wall clock: %s took %.02fs\n%!"
                   test_filename wall_clock_duration

let is_test filename =
  let input_channel = open_in filename in
  let lexbuf = Lexing.from_channel input_channel in
  Fun.protect ~finally:(fun () -> close_in input_channel) begin fun () ->
    Tsl_lexer.is_test lexbuf
  end

let ignored s =
  s = "" || s.[0] = '_' || s.[0] = '.'

let sort_strings = List.sort String.compare

let find_test_dirs dir =
  let res = ref [] in
  let rec loop dir =
    let contains_tests = ref false in
    Array.iter (fun s ->
        if ignored s then ()
        else begin
          let s = dir ^ "/" ^ s in
          if Sys.is_directory s then loop s
          else if not !contains_tests && is_test s then contains_tests := true
        end
      ) (Sys.readdir dir);
    if !contains_tests then res := dir :: !res
  in
  loop dir;
  sort_strings !res

let list_tests dir =
  let res = ref [] in
  if Sys.is_directory dir then begin
    Array.iter (fun s ->
        if ignored s then ()
        else begin
          let s' = dir ^ "/" ^ s in
          if Sys.is_directory s' || not (is_test s') then ()
          else res := s :: !res
        end
      ) (Sys.readdir dir)
  end;
  sort_strings !res

let () =
  Actions.init ();
  Builtin_actions.init ();
  Builtin_variables.init ();
  Ocaml_actions.init ();
  Ocaml_modifiers.init ();
  Ocaml_tests.init ();
  Ocaml_variables.init ();
  Strace.init ();
  init_tests_to_skip()

let () =
  let failed = ref false in
  let work_done = ref false in
  let list_tests dir =
    match list_tests dir with
    | [] -> failed := true
    | res -> List.iter print_endline res
  in
  let find_test_dirs dir = List.iter print_endline (find_test_dirs dir) in
  let doit f x = work_done := true; f x in
  List.iter (doit find_test_dirs) Options.find_test_dirs;
  List.iter (doit list_tests) Options.list_tests;
  let do_file =
    if Options.translate then
      Translate.file ~style:Options.style ~compact:Options.compact
    else
      test_file
  in
  List.iter (doit do_file) Options.files_to_test;
  if not !work_done then print_usage();
  if !failed || not !work_done then exit 1
