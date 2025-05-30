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

(* Generation of bytecode + relocation information *)

open Config
open Misc
open Blambda
open Instruct
open Opcodes
open Cmo_format
module String = Misc.Stdlib.String

type error = Not_compatible_32 of (string * string)
exception Error of error

(* marshal and possibly check 32bit compat *)
let marshal_to_channel_with_possibly_32bit_compat ~filename ~kind outchan obj =
  try
    Marshal.to_channel outchan obj
      (if !Clflags.bytecode_compatible_32
       then [Marshal.Compat_32] else [])
  with Failure _ ->
    raise (Error (Not_compatible_32 (filename, kind)))


let report_error ppf (file, kind) =
  Format.fprintf ppf "Generated %s %S cannot be used on a 32-bit platform"
                     kind file
let () =
  Location.register_error_of_exn
    (function
      | Error (Not_compatible_32 info) ->
          Some (Location.error_of_printer_file report_error info)
      | _ ->
          None
    )

(* Buffering of bytecode *)
let out_buffer = ref(LongString.create 0)
and out_position = ref 0

let extend_buffer needed =
  let size = LongString.length !out_buffer in
  let new_size = ref(max size 16) (* we need new_size > 0 *) in
  while needed >= !new_size do new_size := 2 * !new_size done;
  let new_buffer = LongString.create !new_size in
  LongString.blit !out_buffer 0 new_buffer 0 (LongString.length !out_buffer);
  out_buffer := new_buffer

let out_word b1 b2 b3 b4 =
  let p = !out_position in
  if p+3 >= LongString.length !out_buffer then extend_buffer (p+3);
  LongString.set !out_buffer p (Char.unsafe_chr b1);
  LongString.set !out_buffer (p+1) (Char.unsafe_chr b2);
  LongString.set !out_buffer (p+2) (Char.unsafe_chr b3);
  LongString.set !out_buffer (p+3) (Char.unsafe_chr b4);
  out_position := p + 4

let out opcode =
  out_word opcode 0 0 0


exception AsInt

let const_as_int = function
  | Const_base(Const_int i) -> i
  | Const_base(Const_char c) -> Char.code c
  | _ -> raise AsInt

let is_immed i = immed_min <= i && i <= immed_max
let is_immed_const k =
  try
    is_immed (const_as_int k)
  with
  | AsInt -> false


let out_int n =
  out_word n (n asr 8) (n asr 16) (n asr 24)

let out_const c =
  try
    out_int (const_as_int c)
  with
  | AsInt -> Misc.fatal_error "Emitcode.const_as_int"


(* Handling of local labels and backpatching *)

type label_definition =
    Label_defined of int
  | Label_undefined of (int * int) list

let label_table  = ref ([| |] : label_definition array)

let extend_label_table needed =
  let size = Array.length !label_table in
  let new_size = ref(max size 16) (* we need new_size > 0 *) in
  while needed >= !new_size do new_size := 2 * !new_size done;
  let new_table = Array.make !new_size (Label_undefined []) in
  Array.blit !label_table 0 new_table 0 (Array.length !label_table);
  label_table := new_table

let backpatch (pos, orig) =
  let displ = (!out_position - orig) asr 2 in
  LongString.set !out_buffer pos (Char.unsafe_chr displ);
  LongString.set !out_buffer (pos+1) (Char.unsafe_chr (displ asr 8));
  LongString.set !out_buffer (pos+2) (Char.unsafe_chr (displ asr 16));
  LongString.set !out_buffer (pos+3) (Char.unsafe_chr (displ asr 24))

let define_label lbl =
  if lbl >= Array.length !label_table then extend_label_table lbl;
  match (!label_table).(lbl) with
    Label_defined _ ->
      fatal_error "Emitcode.define_label"
  | Label_undefined patchlist ->
      List.iter backpatch patchlist;
      (!label_table).(lbl) <- Label_defined !out_position

let out_label_with_orig orig lbl =
  if lbl >= Array.length !label_table then extend_label_table lbl;
  match (!label_table).(lbl) with
    Label_defined def ->
      out_int((def - orig) asr 2)
  | Label_undefined patchlist ->
      (!label_table).(lbl) <-
         Label_undefined((!out_position, orig) :: patchlist);
      out_int 0

let out_label l = out_label_with_orig !out_position l

(* Relocation information *)

let reloc_info = ref ([] : (reloc_info * int) list)

let enter info =
  reloc_info := (info, !out_position) :: !reloc_info

let slot_for_literal sc =
  enter (Reloc_literal sc);
  out_int 0
and slot_for_getglobal cu =
  let reloc_info = Reloc_getcompunit cu in
  enter reloc_info;
  out_int 0
and slot_for_getpredef id =
  let name = Ident.name id in
  let reloc_info = Reloc_getpredef (Predef_exn name) in
  enter reloc_info;
  out_int 0
and slot_for_setglobal cu =
  let reloc_info = Reloc_setcompunit cu in
  enter reloc_info;
  out_int 0
and slot_for_c_prim name =
  enter (Reloc_primitive name);
  out_int 0

(* Debugging events *)

let events = ref ([] : debug_event list)
let debug_dirs = ref String.Set.empty

let record_event ev =
  let path = ev.ev_loc.Location.loc_start.Lexing.pos_fname in
  let abspath = Location.absolute_path path in
  debug_dirs := String.Set.add (Filename.dirname abspath) !debug_dirs;
  if Filename.is_relative path then begin
    let cwd = Location.rewrite_absolute_path (Sys.getcwd ()) in
    debug_dirs := String.Set.add cwd !debug_dirs;
  end;
  ev.ev_pos <- !out_position;
  events := ev :: !events

(* Initialization *)

let clear() =
  out_position := 0;
  label_table := [||];
  reloc_info := [];
  debug_dirs := String.Set.empty;
  events := [];
  out_buffer := LongString.create 0

let init () =
  clear ();
  label_table := Array.make 16 (Label_undefined []);
  out_buffer := LongString.create 1024

(* Emission of one instruction *)

let emit_comp = function
| Eq -> out opEQ         | Neq -> out opNEQ
| Ltint -> out opLTINT   | Leint -> out opLEINT
| Gtint -> out opGTINT   | Geint -> out opGEINT
| Ultint -> out opULTINT | Ugeint -> out opUGEINT

and emit_branch_comp = function
| Eq -> out opBEQ         | Neq -> out opBNEQ
| Ltint -> out opBLTINT   | Leint -> out opBLEINT
| Gtint -> out opBGTINT   | Geint -> out opBGEINT
| Ultint -> out opBULTINT | Ugeint -> out opBUGEINT

let negate_comparison = function
  | Eq -> Neq
  | Neq -> Eq
  | Ltint -> Geint
  | Leint -> Gtint
  | Gtint -> Leint
  | Geint -> Ltint
  | Ultint -> Ugeint
  | Ugeint -> Ultint

let runtime5_only () =
  if not Config.runtime5 then
    Misc.fatal_error "Effect primitives are only supported on runtime5"

let emit_instr = function
    Klabel lbl -> define_label lbl
  | Kacc n ->
      if n < 8 then out(opACC0 + n) else (out opACC; out_int n)
  | Kenvacc n ->
      if n >= 1 && n <= 4
      then out(opENVACC1 + n - 1)
      else (out opENVACC; out_int n)
  | Kpush ->
      out opPUSH
  | Kpop n ->
      out opPOP; out_int n
  | Kassign n ->
      out opASSIGN; out_int n
  | Kpush_retaddr lbl -> out opPUSH_RETADDR; out_label lbl
  | Kapply n ->
      if n < 4 then out(opAPPLY1 + n - 1) else (out opAPPLY; out_int n)
  | Kappterm(n, sz) ->
      if n < 4 then (out(opAPPTERM1 + n - 1); out_int sz)
               else (out opAPPTERM; out_int n; out_int sz)
  | Kreturn n -> out opRETURN; out_int n
  | Krestart -> out opRESTART
  | Kgrab n -> out opGRAB; out_int n
  | Kclosure(lbl, n) -> out opCLOSURE; out_int n; out_label lbl
  | Kclosurerec(lbls, n) ->
      out opCLOSUREREC; out_int (List.length lbls); out_int n;
      let org = !out_position in
      List.iter (out_label_with_orig org) lbls
  | Koffsetclosure ofs ->
      if ofs = -3 || ofs = 0 || ofs = 3
      then out (opOFFSETCLOSURE0 + ofs / 3)
      else (out opOFFSETCLOSURE; out_int ofs)
  | Kgetglobal cu -> out opGETGLOBAL; slot_for_getglobal cu
  | Ksetglobal cu -> out opSETGLOBAL; slot_for_setglobal cu
  | Kgetpredef id -> out opGETGLOBAL; slot_for_getpredef id
  | Kconst sc ->
      begin match sc with
        Const_base(Const_int i) when is_immed i ->
          if i >= 0 && i <= 3
          then out (opCONST0 + i)
          else (out opCONSTINT; out_int i)
      | Const_base(Const_char c) ->
          out opCONSTINT; out_int (Char.code c)
      | Const_block(t, []) ->
          if t = 0 then out opATOM0 else (out opATOM; out_int t)
      | _ ->
          out opGETGLOBAL; slot_for_literal sc
      end
  | Kmakeblock(n, t) ->
      if n = 0 then
        if t = 0 then out opATOM0 else (out opATOM; out_int t)
      else if n < 4 then (out(opMAKEBLOCK1 + n - 1); out_int t)
      else (out opMAKEBLOCK; out_int n; out_int t)
  | Kmake_faux_mixedblock(n, t) ->
      assert (n > 0);
      out opMAKE_FAUX_MIXEDBLOCK; out_int n; out_int t
  | Kgetfield n ->
      if n < 4 then out(opGETFIELD0 + n) else (out opGETFIELD; out_int n)
  | Ksetfield n ->
      if n < 4 then out(opSETFIELD0 + n) else (out opSETFIELD; out_int n)
  | Kmakefloatblock(n) ->
      if n = 0 then out opATOM0 else (out opMAKEFLOATBLOCK; out_int n)
  | Kgetfloatfield n -> out opGETFLOATFIELD; out_int n
  | Ksetfloatfield n -> out opSETFLOATFIELD; out_int n
  | Kvectlength -> out opVECTLENGTH
  | Kgetvectitem -> out opGETVECTITEM
  | Ksetvectitem -> out opSETVECTITEM
  | Kgetstringchar -> out opGETSTRINGCHAR
  | Kgetbyteschar -> out opGETBYTESCHAR
  | Ksetbyteschar -> out opSETBYTESCHAR
  | Kbranch lbl -> out opBRANCH; out_label lbl
  | Kbranchif lbl -> out opBRANCHIF; out_label lbl
  | Kbranchifnot lbl -> out opBRANCHIFNOT; out_label lbl
  | Kstrictbranchif lbl -> out opBRANCHIF; out_label lbl
  | Kstrictbranchifnot lbl -> out opBRANCHIFNOT; out_label lbl
  | Kswitch(tbl_const, tbl_block) ->
      out opSWITCH;
      out_int (Array.length tbl_const + (Array.length tbl_block lsl 16));
      let org = !out_position in
      Array.iter (out_label_with_orig org) tbl_const;
      Array.iter (out_label_with_orig org) tbl_block
  | Kboolnot -> out opBOOLNOT
  | Kpushtrap lbl -> out opPUSHTRAP; out_label lbl
  | Kpoptrap -> out opPOPTRAP
  | Kraise Raise_regular -> out opRAISE
  | Kraise Raise_reraise -> out opRERAISE
  | Kraise Raise_notrace -> out opRAISE_NOTRACE
  | Kcheck_signals -> out opCHECK_SIGNALS
  | Kccall(name, n) ->
      if n <= 5
      then (out (opC_CALL1 + n - 1); slot_for_c_prim name)
      else (out opC_CALLN; out_int n; slot_for_c_prim name)
  | Knegint -> out opNEGINT  | Kaddint -> out opADDINT
  | Ksubint -> out opSUBINT  | Kmulint -> out opMULINT
  | Kdivint -> out opDIVINT  | Kmodint -> out opMODINT
  | Kandint -> out opANDINT  | Korint -> out opORINT
  | Kxorint -> out opXORINT  | Klslint -> out opLSLINT
  | Klsrint -> out opLSRINT  | Kasrint -> out opASRINT
  | Kintcomp c -> emit_comp c
  | Koffsetint n -> out opOFFSETINT; out_int n
  | Koffsetref n -> out opOFFSETREF; out_int n
  | Kisint -> out opISINT
  | Kgetmethod -> out opGETMETHOD
  | Kgetpubmet tag -> out opGETPUBMET; out_int tag; out_int 0
  | Kgetdynmet -> out opGETDYNMET
  | Kevent ev -> record_event ev
  | Kperform -> runtime5_only (); out opPERFORM
  | Kresume -> runtime5_only (); out opRESUME
  | Kresumeterm n -> runtime5_only (); out opRESUMETERM; out_int n
  | Kreperformterm n -> runtime5_only (); out opREPERFORMTERM; out_int n
  | Kstop -> out opSTOP

(* Emission of a list of instructions. Include some peephole optimization. *)

let remerge_events ev1 = function
  | Kevent ev2 :: c ->
    Kevent (Bytegen.merge_events ev1 ev2) :: c
  | c -> Kevent ev1 :: c

let rec emit = function
    [] -> ()
  (* Peephole optimizations *)
(* optimization of integer tests *)
  | Kpush::Kconst k::Kintcomp c::Kbranchif lbl::rem
      when is_immed_const k ->
        emit_branch_comp c ;
        out_const k ;
        out_label lbl ;
        emit rem
  | Kpush::Kconst k::Kintcomp c::Kbranchifnot lbl::rem
      when is_immed_const k ->
        emit_branch_comp (negate_comparison c) ;
        out_const k ;
        out_label lbl ;
        emit rem
(* same for range tests *)
  | Kpush::Kconst k::Kintcomp Ultint::Kbranchif lbl::rem
      when is_immed_const k ->
        out opBULTINT ;
        out_const k ;
        out_label lbl ;
        emit rem
  | Kpush::Kconst k::Kintcomp Ultint::Kbranchifnot lbl::rem
      when is_immed_const k ->
        out opBUGEINT ;
        out_const k ;
        out_label lbl ;
        emit rem
(* Some special case of push ; i ; ret generated by the match compiler *)
  | Kpush :: Kacc 0 :: Kreturn m :: c ->
      emit (Kreturn (m-1) :: c)
(* General push then access scheme *)
  | Kpush :: Kacc n :: c ->
      if n < 8 then out(opPUSHACC0 + n) else (out opPUSHACC; out_int n);
      emit c
  | Kpush :: Kenvacc n :: c ->
      if n >= 1 && n < 4
      then out(opPUSHENVACC1 + n - 1)
      else (out opPUSHENVACC; out_int n);
      emit c
  | Kpush :: Koffsetclosure ofs :: c ->
      if ofs = -3 || ofs = 0 || ofs = 3
      then out(opPUSHOFFSETCLOSURE0 + ofs / 3)
      else (out opPUSHOFFSETCLOSURE; out_int ofs);
      emit c
  | Kpush :: Kgetglobal id :: Kgetfield n :: c ->
      out opPUSHGETGLOBALFIELD; slot_for_getglobal id; out_int n; emit c
  | Kpush :: Kgetglobal id :: c ->
      out opPUSHGETGLOBAL; slot_for_getglobal id; emit c
  | Kpush :: Kconst sc :: c ->
      begin match sc with
        Const_base(Const_int i) when is_immed i ->
          if i >= 0 && i <= 3
          then out (opPUSHCONST0 + i)
          else (out opPUSHCONSTINT; out_int i)
      | Const_base(Const_char c) ->
          out opPUSHCONSTINT; out_int(Char.code c)
      | Const_block(t, []) ->
          if t = 0 then out opPUSHATOM0 else (out opPUSHATOM; out_int t)
      | _ ->
          out opPUSHGETGLOBAL; slot_for_literal sc
      end;
      emit c
  | Kpush :: (Kevent ({ev_kind = Event_before} as ev)) ::
    (Kgetglobal _ as instr1) :: (Kgetfield _ as instr2) :: c ->
      emit (Kpush :: instr1 :: instr2 :: remerge_events ev c)
  | Kpush :: (Kevent ({ev_kind = Event_before} as ev)) ::
    (Kacc _ | Kenvacc _ | Koffsetclosure _ | Kgetglobal _ | Kconst _ as instr)::
    c ->
      emit (Kpush :: instr :: remerge_events ev c)
  | Kgetglobal id :: Kgetfield n :: c ->
      out opGETGLOBALFIELD; slot_for_getglobal id; out_int n; emit c
  (* Default case *)
  | instr :: c ->
      emit_instr instr; emit c

(* Emission to a file *)

let to_file outchan cu artifact_info ~required_globals ~main_module_block_format
          ~arg_descr code =
  init();
  Fun.protect ~finally:clear (fun () ->
  output_string outchan cmo_magic_number;
  let pos_depl = pos_out outchan in
  output_binary_int outchan 0;
  let pos_code = pos_out outchan in
  emit code;
  LongString.output outchan !out_buffer 0 !out_position;
  let (pos_debug, size_debug) =
    if !Clflags.debug then begin
      let filename = Unit_info.Artifact.filename artifact_info in
      debug_dirs := String.Set.add
          (Filename.dirname (Location.absolute_path filename))
        !debug_dirs;
      let p = pos_out outchan in
      (* CR ocaml 5 compressed-marshal mshinwell:
         Compression not supported in the OCaml 4 runtime
      Compression.output_value outchan !events;
      Compression.output_value outchan (String.Set.elements !debug_dirs);
      *)
(* BACKPORT BEGIN *)
      Marshal.(to_channel outchan !events []);
      Marshal.(to_channel outchan (String.Set.elements !debug_dirs)
                          []);
(* BACKPORT END *)
      (p, pos_out outchan - p)
    end else
      (0, 0) in
  let compunit =
    { cu_name = cu;
      cu_pos = pos_code;
      cu_codesize = !out_position;
      cu_reloc = List.rev !reloc_info;
      cu_arg_descr = arg_descr;
      cu_imports = Env.imports() |> Array.of_list;
      cu_format = main_module_block_format;
      cu_primitives = List.map Primitive.byte_name
                               !Translmod.primitive_declarations;
      cu_required_compunits = Compilation_unit.Set.elements required_globals;
      cu_force_link = !Clflags.link_everything;
      cu_debug = pos_debug;
      cu_debugsize = size_debug } in
  let pos_compunit = pos_out outchan in
  let () =
    (* Remove any cached abbreviation expansion before marshaling.
       See doc-comment for [Types.abbrev_memo] *)
    Btype.cleanup_abbrev ();
    marshal_to_channel_with_possibly_32bit_compat
      ~filename:(Unit_info.Artifact.filename artifact_info)
      ~kind:"bytecode unit"
      outchan compunit
  in
  seek_out outchan pos_depl;
  output_binary_int outchan pos_compunit)

(* Emission to a memory block *)

let to_memory instrs =
  init();
  Fun.protect ~finally:clear (fun () ->
  emit instrs;
  let code = LongString.create !out_position in
  LongString.blit !out_buffer 0 code 0 !out_position;
  let reloc = List.rev !reloc_info in
  let events = !events in
  (code, reloc, events))

(* Emission to a file for a packed library *)

let to_packed_file outchan code =
  init ();
  Fun.protect ~finally:clear (fun () ->
  emit code;
  LongString.output outchan !out_buffer 0 !out_position;
  let reloc = List.rev !reloc_info in
  let events = !events in
  let debug_dirs = !debug_dirs in
  let size = !out_position in
  (size, reloc, events, debug_dirs))
