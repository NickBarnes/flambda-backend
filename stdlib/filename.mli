# 2 "filename.mli"
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

@@ portable

open! Stdlib

(** Operations on file names. *)

val current_dir_name : string
(** The conventional name for the current directory (e.g. [.] in Unix). *)

val parent_dir_name : string
(** The conventional name for the parent of the current directory
   (e.g. [..] in Unix). *)

val dir_sep : string
(** The directory separator (e.g. [/] in Unix).

    @since 3.11.2 *)

val concat : string -> string -> string
(** [concat dir file] returns a file name that designates file
   [file] in directory [dir]. *)

val is_relative : string -> bool
(** Return [true] if the file name is relative to the current
   directory, [false] if it is absolute (i.e. in Unix, starts
   with [/]). *)

val is_implicit : string -> bool
(** Return [true] if the file name is relative and does not start
   with an explicit reference to the current directory ([./] or
   [../] in Unix), [false] if it starts with an explicit reference
   to the root directory or the current directory. *)

val check_suffix : string -> string -> bool
(** [check_suffix name suff] returns [true] if the filename [name]
    ends with the suffix [suff].

    Under Windows ports (including Cygwin), comparison is
    case-insensitive, relying on [String.lowercase_ascii].  Note that
    this does not match exactly the interpretation of case-insensitive
    filename equivalence from Windows.  *)

val chop_suffix : string -> string -> string
(** [chop_suffix name suff] removes the suffix [suff] from
    the filename [name].
    @raise Invalid_argument if [name] does not end with the suffix [suff].
*)

val chop_suffix_opt: suffix:string -> string -> string option
(** [chop_suffix_opt ~suffix filename] removes the suffix from
    the [filename] if possible, or returns [None] if the
    filename does not end with the suffix.

    Under Windows ports (including Cygwin), comparison is
    case-insensitive, relying on [String.lowercase_ascii].  Note that
    this does not match exactly the interpretation of case-insensitive
    filename equivalence from Windows.

    @since 4.08
*)


val extension : string -> string
(** [extension name] is the shortest suffix [ext] of [name0] where:

    - [name0] is the longest suffix of [name] that does not
      contain a directory separator;
    - [ext] starts with a period;
    - [ext] is preceded by at least one non-period character
      in [name0].

    If such a suffix does not exist, [extension name] is the empty
    string.

    @since 4.04
*)

val remove_extension : string -> string
(** Return the given file name without its extension, as defined
    in {!Filename.extension}. If the extension is empty, the function
    returns the given file name.

    The following invariant holds for any file name [s]:

    [remove_extension s ^ extension s = s]

    @since 4.04
*)

val chop_extension : string -> string
(** Same as {!Filename.remove_extension}, but raise [Invalid_argument]
    if the given name has an empty extension. *)


val basename : string -> string
(** Split a file name into directory name / base file name.
   If [name] is a valid file name, then [concat (dirname name) (basename name)]
   returns a file name which is equivalent to [name]. Moreover,
   after setting the current directory to [dirname name] (with {!Sys.chdir}),
   references to [basename name] (which is a relative file name)
   designate the same file as [name] before the call to {!Sys.chdir}.

   This function conforms to the specification of POSIX.1-2008 for the
   [basename] utility. *)

val dirname : string -> string
(** See {!Filename.basename}.
   This function conforms to the specification of POSIX.1-2008 for the
   [dirname] utility. *)

val null : string
(** [null] is ["/dev/null"] on POSIX and ["NUL"] on Windows. It represents a
    file on the OS that discards all writes and returns end of file on reads.

    @since 4.10 *)

val temp_file : ?temp_dir: string -> string -> string -> string
(** [temp_file prefix suffix] returns the name of a
   fresh temporary file in the temporary directory.
   The base name of the temporary file is formed by concatenating
   [prefix], then a suitably chosen integer number, then [suffix].
   The optional argument [temp_dir] indicates the temporary directory
   to use, defaulting to the current result of {!Filename.get_temp_dir_name}.
   The temporary file is created empty, with permissions [0o600]
   (readable and writable only by the file owner).  The file is
   guaranteed to be different from any other file that existed when
   [temp_file] was called.
   @raise Sys_error if the file could not be created.
   @before 3.11.2 no ?temp_dir optional argument
*)

val open_temp_file :
      ?mode: open_flag list -> ?perms: int -> ?temp_dir: string -> string ->
      string -> string * out_channel
(** Same as {!Filename.temp_file}, but returns both the name of a fresh
   temporary file, and an output channel opened (atomically) on
   this file.  This function is more secure than [temp_file]: there
   is no risk that the temporary file will be modified (e.g. replaced
   by a symbolic link) before the program opens it.  The optional argument
   [mode] is a list of additional flags to control the opening of the file.
   It can contain one or several of [Open_append], [Open_binary],
   and [Open_text].  The default is [[Open_text]] (open in text mode). The
   file is created with permissions [perms] (defaults to readable and
   writable only by the file owner, [0o600]).

   @raise Sys_error if the file could not be opened.
   @before 4.03 no ?perms optional argument
   @before 3.11.2 no ?temp_dir optional argument
*)

val temp_dir : ?temp_dir: string -> ?perms:int  -> string -> string -> string
(** [temp_dir prefix suffix] creates and returns the name of a fresh
   temporary directory with permissions [perms] (defaults to 0o700)
   inside [temp_dir].  The base name of the temporary directory is
   formed by concatenating [prefix], then a suitably chosen integer
   number, then [suffix].  The optional argument [temp_dir] indicates
   the temporary directory to use, defaulting to the current result of
   {!Filename.get_temp_dir_name}.  The temporary directory is created
   empty, with permissions [0o700] (readable, writable, and searchable
   only by the file owner).  The directory is guaranteed to be
   different from any other directory that existed when [temp_dir] was
   called.

   If temp_dir does not exist, this function does not create it.  Instead,
   it raises Sys_error.

   @raise Sys_error if the directory could not be created.
   @since 5.1
*)

val get_temp_dir_name : unit -> string
(** The name of the temporary directory:
    Under Unix, the value of the [TMPDIR] environment variable, or "/tmp"
    if the variable is not set.
    Under Windows, the value of the [TEMP] environment variable, or "."
    if the variable is not set.
    The temporary directory can be changed with {!Filename.set_temp_dir_name}.
    @since 4.00
*)

val set_temp_dir_name : string -> unit
(** Change the temporary directory returned by {!Filename.get_temp_dir_name}
    and used by {!Filename.temp_file} and {!Filename.open_temp_file}.
    The temporary directory is a domain-local value which is inherited
    by child domains.
    @since 4.00
*)

val quote : string -> string
(** Return a quoted version of a file name, suitable for use as
    one argument in a command line, escaping all meta-characters.
    Warning: under Windows, the output is only suitable for use
    with programs that follow the standard Windows quoting
    conventions.
 *)

val quote_command :
       string -> ?stdin:string -> ?stdout:string -> ?stderr:string
              -> string list -> string
(** [quote_command cmd args] returns a quoted command line, suitable
    for use as an argument to {!Sys.command}, {!Unix.system}, and the
    {!Unix.open_process} functions.

    The string [cmd] is the command to call.  The list [args] is
    the list of arguments to pass to this command.  It can be empty.

    The optional arguments [?stdin] and [?stdout] and [?stderr] are
    file names used to redirect the standard input, the standard
    output, or the standard error of the command.
    If [~stdin:f] is given, a redirection [< f] is performed and the
    standard input of the command reads from file [f].
    If [~stdout:f] is given, a redirection [> f] is performed and the
    standard output of the command is written to file [f].
    If [~stderr:f] is given, a redirection [2> f] is performed and the
    standard error of the command is written to file [f].
    If both [~stdout:f] and [~stderr:f] are given, with the exact
    same file name [f], a [2>&1] redirection is performed so that the
    standard output and the standard error of the command are interleaved
    and redirected to the same file [f].

    Under Unix and Cygwin, the command, the arguments, and the redirections
    if any are quoted using {!Filename.quote}, then concatenated.
    Under Win32, additional quoting is performed as required by the
    [cmd.exe] shell that is called by {!Sys.command}.
    @raise Failure if the command cannot be escaped on the current platform.
    @since 4.10
*)
