(* This program simply runs a register allocator on the all the functions saved
   in a .cmir-cfg-regalloc file. *)

module List = ListLabels

type register_allocator =
  | GI
  | IRC
  | LS

let register_allocators = [GI; IRC; LS]

let string_of_register_allocator = function
  | GI -> "gi"
  | IRC -> "irc"
  | LS -> "ls"

let allocators =
  List.map register_allocators ~f:(fun ra ->
      string_of_register_allocator ra, ra)

type config =
  { register_allocator : register_allocator;
    validation : bool;
    debug_output : bool;
    csv_output : bool
  }

external time_include_children : bool -> float
  = "caml_sys_time_include_children"

let cpu_time () = time_include_children false

let process_function (config : config) (cfg_with_layout : Cfg_with_layout.t)
    (cmm_label : Label.t) (reg_stamp : int) (relocatable_regs : Reg.t list) =
  if config.debug_output
  then
    Printf.eprintf "  processing function %S...\n%!"
      (Cfg_with_layout.cfg cfg_with_layout).fun_name;
  let num_regs = List.length relocatable_regs in
  if config.debug_output
  then Printf.eprintf "    %d register(s)...\n%!" num_regs;
  Cmm.reset ();
  Cmm.set_label cmm_label;
  Reg.For_testing.set_state ~stamp:reg_stamp ~relocatable_regs;
  let cfg_with_infos = Cfg_with_infos.make cfg_with_layout in
  let cfg_description =
    match config.validation with
    | false -> None
    | true -> Some (Regalloc_validate.Description.create cfg_with_layout)
  in
  let start_time = cpu_time () in
  let (_ : Cfg_with_infos.t) =
    match config.register_allocator with
    | GI -> Regalloc_gi.run cfg_with_infos
    | IRC -> Regalloc_irc.run cfg_with_infos
    | LS -> Regalloc_ls.run cfg_with_infos
  in
  let end_time = cpu_time () in
  (match cfg_description with
  | None -> ()
  | Some cfg_description ->
    let (_ : Cfg_with_layout.t) =
      Regalloc_validate.run cfg_description cfg_with_layout
    in
    ());
  let duration = end_time -. start_time in
  if config.csv_output
  then begin
    Printf.printf "%s;%s;%d;%g\n%!"
      (string_of_register_allocator config.register_allocator)
      (Cfg_with_layout.cfg cfg_with_layout).fun_name num_regs duration
  end;
  if config.debug_output
  then Printf.eprintf "  register allocation took %gs...\n%!" duration;
  ()

let process_file (file : string) (config : config) =
  if config.debug_output then Printf.eprintf "processing file %S...\n%!" file;
  let unit_info, _digest = Cfg_format.restore file in
  List.iter unit_info.items ~f:(fun (item : Cfg_format.cfg_item_info) ->
      begin
        match item with
        | Cfg _ -> ()
        | Data _ -> ()
        | Cfg_before_regalloc
            { cfg_with_layout_and_relocatable_regs; cmm_label; reg_stamp } ->
          let cfg_with_layout, relocatable_regs =
            cfg_with_layout_and_relocatable_regs
          in
          process_function config cfg_with_layout cmm_label reg_stamp
            relocatable_regs
      end)

let () =
  let register_allocator = ref None in
  let set_register_allocator str =
    match List.assoc_opt str allocators with
    | None -> assert false
    | Some allocator -> register_allocator := Some allocator
  in
  let validate = ref false in
  let csv_output = ref false in
  let debug_output = ref false in
  let files = ref [] in
  let args : (Arg.key * Arg.spec * Arg.doc) list =
    [ ( "-regalloc",
        Arg.Symbol (List.map allocators ~f:fst, set_register_allocator),
        "  Choose register allocator" );
      "-validate", Arg.Set validate, "Enable validation";
      "-csv-output", Arg.Set csv_output, "Enable CSV output";
      "-debug-output", Arg.Set debug_output, "Enable debug output" ]
  in
  let anonymous file = files := file :: !files in
  Arg.parse args anonymous
    "run register allocation on a .cmir-cfg-regalloc file";
  match !register_allocator with
  | None ->
    Printf.eprintf
      "*** error: register allocator was not set (use -regalloc)\n%!";
    exit 1
  | Some register_allocator ->
    let config =
      { register_allocator;
        validation = !validate;
        csv_output = !csv_output;
        debug_output = !debug_output
      }
    in
    if config.csv_output
    then begin
      Printf.printf "allocator;function;registers;duration\n%!"
    end;
    List.iter (List.rev !files) ~f:(fun file -> process_file file config)
