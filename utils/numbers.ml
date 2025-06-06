(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                       Pierre Chambart, OCamlPro                        *)
(*           Mark Shinwell and Leo White, Jane Street Europe              *)
(*                                                                        *)
(*   Copyright 2013--2016 OCamlPro SAS                                    *)
(*   Copyright 2014--2016 Jane Street Group LLC                           *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

module Int_base = Identifiable.Make (struct
  type t = int

  let compare = Int.compare
  let output oc x = Printf.fprintf oc "%i" x
  let hash i = i
  let equal (i : int) j = i = j
  let print = Format.pp_print_int
end)

module Int = struct
  type t = int

  include Int_base

  let rec zero_to_n n =
    if n < 0 then Set.empty else Set.add n (zero_to_n (n-1))

  let to_string n = Int.to_string n
end

module Int8 = struct
  type t = int

  let zero = 0
  let one = 1

  let of_int_exn i =
    if i < -(1 lsl 7) || i > ((1 lsl 7) - 1) then
      Misc.fatal_errorf "Int8.of_int_exn: %d is out of range" i
    else
      i

  let to_int i = i

  let print ppf t = Format.pp_print_int ppf t
end

module Uint8 = struct
  type t = int

  let print ppf t = Format.pp_print_int ppf t

  let zero = 0

  let one = 1

  let of_nonnegative_int_exn i =
    if i < 0 || i > (1 lsl 8) - 1
    then Misc.fatal_errorf "Uint8.of_nonnegative_int_exn: %d is out of range" i
    else i

  let to_int i = i
end

module Int16 = struct
  type t = int

  let zero = 0

  let one = 1

  let of_int_exn i =
    if i < -(1 lsl 15) || i > ((1 lsl 15) - 1) then
      Misc.fatal_errorf "Int16.of_int_exn: %d is out of range" i
    else
      i

  let lower_int64 = Int64.neg (Int64.shift_left Int64.one 15)
  let upper_int64 = Int64.sub (Int64.shift_left Int64.one 15) Int64.one

  let of_int64_exn i =
    if Int64.compare i lower_int64 < 0
        || Int64.compare i upper_int64 > 0
    then
      Misc.fatal_errorf "Int16.of_int64_exn: %Ld is out of range" i
    else
      Int64.to_int i

  let to_int t = t

  let print ppf t = Format.pp_print_int ppf t
end

module Uint16 = struct
  type t = int

  let print ppf t = Format.pp_print_int ppf t

  let of_nonnegative_int_exn i =
    if i < 0 || i > (1 lsl 16) - 1
    then Misc.fatal_errorf "Uint16.of_nonnegative_int_exn: %d is out of range" i
    else i

  let upper_int64 = Int64.sub (Int64.shift_left Int64.one 16) Int64.one

  let of_nonnegative_int64_exn i =
    if Int64.compare i 0L < 0 || Int64.compare i upper_int64 > 0
    then
      Misc.fatal_errorf "Uint16.of_nonnegative_int64_exn: %Ld is out of range" i
    else Int64.to_int i

  let to_int t = t
end

module Uint32 = struct
  type t = Int64.t

  let zero = 0L

  let print ppf t = Format.fprintf ppf "0x%Lx" t

  let upper_int64 = Int64.sub (Int64.shift_left Int64.one 32) Int64.one

  let of_nonnegative_int_exn i =
    if i < 0
    then Misc.fatal_errorf "Uint32.of_nonnegative_int_exn: %d is out of range" i
    else
      let i64 = Int64.of_int i in
      if Int64.compare i64 upper_int64 > 0
      then
        Misc.fatal_errorf "Uint32.of_nonnegative_int_exn: %d is out of range" i
      else i64

  let of_nonnegative_int64_exn i =
    if Int64.compare i 0L < 0 || Int64.compare i upper_int64 > 0
    then
      Misc.fatal_errorf "Uint32.of_nonnegative_int64_exn: %Ld is out of range" i
    else i

  let of_nonnegative_int32_exn i =
    if Int32.compare i 0l < 0
    then
      Misc.fatal_errorf "Uint32.of_nonnegative_int32_exn: %ld is out of range" i
    else Int64.of_int32 i

  let to_int64 t = t
end

module Uint64 = struct
  type t = Int64.t

  let zero = 0L

  let succ t = Int64.add 1L t

  let of_nonnegative_int_exn i =
    if i < 0
    then Misc.fatal_errorf "Uint64.of_nonnegative_int_exn: %d is out of range" i
    else Int64.of_int i

  let of_uint8 i = Int64.of_int i

  let of_uint16 i = Int64.of_int i

  let of_uint32 i = i

  let of_nonnegative_int32_exn i =
    if Int32.compare i 0l < 0
    then
      Misc.fatal_errorf "Uint64.of_nonnegative_int32_exn: %ld is out of range" i
    else Int64.of_int32 i

  let of_nonnegative_int64_exn i =
    if Int64.compare i 0L < 0
    then
      Misc.fatal_errorf "Uint64.of_nonnegative_int64_exn: %Ld is out of range" i
    else i

  let to_int64 t = t

  include Identifiable.Make (struct
    type nonrec t = t

    let compare t1 t2 =
      (* Only a consistent order is needed here *)
      Int64.compare t1 t2

    let equal t1 t2 = compare t1 t2 = 0

    let hash t = Hashtbl.hash t

    let print ppf t = Format.fprintf ppf "0x%Lx" t

    let output _ _ = Misc.fatal_error "Not yet implemented"
  end)
end


module Float = struct
  type t = float

  include Identifiable.Make (struct
    type t = float

    let compare x y = Stdlib.compare x y
    let output oc x = Printf.fprintf oc "%f" x
    let hash f = Hashtbl.hash f
    let equal (i : float) j = i = j
    let print = Format.pp_print_float
  end)
end

module Int64 = struct

  let to_int32_exn n =
    if Int64.compare n (Int64.of_int32 Int32.min_int)  < 0
       || Int64.compare n (Int64.of_int32 Int32.max_int)  > 0
    then Misc.fatal_errorf "Integer %Ld is out of the 32-bit range." n;
    Int64.to_int32 n

end
