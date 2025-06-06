(* TEST
   include stdlib_stable;
   expect;
*)

type r = {mutable a : bytes; b : bytes}

let best_bytes : unit -> bytes @ portable uncontended
    = Obj.magic (fun () -> Bytes.empty)
[%%expect{|
type r = { mutable a : bytes; b : bytes; }
val best_bytes : unit -> bytes @ portable = <fun>
|}]

(* TESTING records *)

(* Reading/writing mutable field from contended record is rejected. Also note
    that the mutation error precedes type error. *)
let foo (r @ contended) = r.a <- 42
[%%expect{|
Line 1, characters 26-27:
1 | let foo (r @ contended) = r.a <- 42
                              ^
Error: This value is "contended" but expected to be "uncontended".
  Hint: In order to write into its mutable fields,
  this record needs to be uncontended.
|}]

let foo (r @ contended) = r.a
[%%expect{|
Line 1, characters 26-27:
1 | let foo (r @ contended) = r.a
                              ^
Error: This value is "contended" but expected to be "shared" or "uncontended".
  Hint: In order to read from its mutable fields,
  this record needs to be at least shared.
|}]

let foo (r @ contended) = {r with a = best_bytes ()}
[%%expect{|
val foo : r @ contended -> r @ contended = <fun>
|}]

let foo (r @ contended) = {r with b = best_bytes ()}
[%%expect{|
Line 1, characters 27-28:
1 | let foo (r @ contended) = {r with b = best_bytes ()}
                               ^
Error: This value is "contended" but expected to be "shared" or "uncontended".
  Hint: In order to read from its mutable fields,
  this record needs to be at least shared.
|}]

(* Writing to a mutable field in a shared record is rejected *)
let foo (r @ shared) = r.a <- 42
[%%expect{|
Line 1, characters 23-24:
1 | let foo (r @ shared) = r.a <- 42
                           ^
Error: This value is "shared" but expected to be "uncontended".
  Hint: In order to write into its mutable fields,
  this record needs to be uncontended.
|}]

(* reading mutable field from shared record is fine *)
let foo (r @ shared) = r.a
[%%expect{|
val foo : r @ shared -> bytes @ shared = <fun>
|}]

let foo (r @ shared) = {r with b = best_bytes ()}
[%%expect{|
val foo : r @ shared -> r @ shared = <fun>
|}]

(* reading immutable field from contended record is fine *)
let foo (r @ contended) = r.b
[%%expect{|
val foo : r @ contended -> bytes @ contended = <fun>
|}]

(* reading immutable field from shared record is fine *)
let foo (r @ shared) = r.b
[%%expect{|
val foo : r @ shared -> bytes @ shared = <fun>
|}]

let foo (r @ shared) = {r with a = best_bytes ()}
[%%expect{|
val foo : r @ shared -> r @ shared = <fun>
|}]

(* Force top level to be uncontended and nonportable *)
let r @ contended = best_bytes ()
[%%expect{|
Line 1, characters 4-33:
1 | let r @ contended = best_bytes ()
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error: This value is "contended" but expected to be "uncontended".
|}]

let r @ shared = best_bytes ()
[%%expect{|
Line 1, characters 4-30:
1 | let r @ shared = best_bytes ()
        ^^^^^^^^^^^^^^^^^^^^^^^^^^
Error: This value is "shared" but expected to be "uncontended".
|}]

let x @ portable = fun a -> a

let y @ portable = x
[%%expect{|
val x : 'a -> 'a = <fun>
Line 3, characters 19-20:
3 | let y @ portable = x
                       ^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over writing mutable field gives nonportable *)
let foo () =
    let r = {a = best_bytes (); b = best_bytes ()} in
    let bar () = r.a <- best_bytes () in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 4, characters 23-26:
4 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over reading mutable field gives nonportable *)
let foo () =
    let r = {a = best_bytes (); b = best_bytes ()} in
    let bar () = let _ = r.a in () in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 4, characters 23-26:
4 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over reading mutable field from shared value is nonportable *)
let foo (r @ shared) =
    let bar () = let _ = r.a in () in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 3, characters 23-26:
3 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over reading immutable field is OK *)
let foo () =
    let r @ portable = {a = best_bytes (); b = best_bytes ()} in
    let bar () = let _ = r.b in () in
    let _ @ portable = bar in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]


(* TESTING arrays *)
(* reading/writing to array requires uncontended *)
let foo (r @ contended) = Array.set r 42 (best_bytes ())
[%%expect{|
Line 1, characters 36-37:
1 | let foo (r @ contended) = Array.set r 42 (best_bytes ())
                                        ^
Error: This value is "contended" but expected to be "uncontended".
|}]
let foo (r @ contended) = Array.get r 42
[%%expect{|
Line 1, characters 36-37:
1 | let foo (r @ contended) = Array.get r 42
                                        ^
Error: This value is "contended" but expected to be "uncontended".
|}]
let foo (r @ contended) =
    match r with
    | [| x; y |] -> ()
[%%expect{|
Line 3, characters 6-16:
3 |     | [| x; y |] -> ()
          ^^^^^^^^^^
Error: This value is "contended" but expected to be "shared" or "uncontended".
  Hint: In order to read from its mutable fields,
  this record needs to be at least shared.
|}]
(* CR modes: Error message should mention array, not record. *)

let foo (r @ shared) = Array.set r 42 (best_bytes ())
[%%expect{|
Line 1, characters 33-34:
1 | let foo (r @ shared) = Array.set r 42 (best_bytes ())
                                     ^
Error: This value is "shared" but expected to be "uncontended".
|}]

(* The signature of Array.get could be generalized to expect shared rather than
   uncontended, but this would require a change to stdlib. For now the following
   test fails *)
(* CR modes: Fix this *)
let foo (r @ shared) = Array.get r 42
[%%expect{|
Line 1, characters 33-34:
1 | let foo (r @ shared) = Array.get r 42
                                     ^
Error: This value is "shared" but expected to be "uncontended".
|}]

(* Reading from a shared array is fine *)
let foo (r @ shared) =
    match r with
    | [| x; y |] -> ()
    | _ -> ()
[%%expect{|
val foo : 'a array @ shared -> unit = <fun>
|}]

(* Closing over write gives nonportable *)
let foo () =
    let r = [| best_bytes (); best_bytes () |] in
    let bar () = Array.set r 0 (best_bytes ()) in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 4, characters 23-26:
4 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over read gives nonportable *)
let foo () =
    let r = [| best_bytes (); best_bytes () |] in
    let bar () = Array.get r 0 in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 4, characters 23-26:
4 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* Closing over Array.length doesn't force nonportable; but that needs a
   modified stdlib. Once modified the test is trivial. So we omit that. *)


(* OTHER TESTS *)
(* Closing over uncontended or shared but doesn't exploit that; the function is still
portable. *)
let foo () =
    let r @ portable uncontended = best_bytes () in
    let bar () = let _ = r in () in
    let _ @ portable = bar in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

let foo () =
    let r @ portable shared = best_bytes () in
    let bar () = let _ = r in () in
    let _ @ portable = bar in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

(* Closing over nonportable forces nonportable. *)
let foo () =
    let r @ nonportable = fun x -> x in
    let bar () = let _ = r in () in
    let _ @ portable = bar in
    ()
[%%expect{|
Line 4, characters 23-26:
4 |     let _ @ portable = bar in
                           ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* closing over nonportable gives nonportable *)
let foo : 'a @ nonportable contended -> (unit -> unit) @ portable = fun a () -> ()
[%%expect{|
Line 1, characters 68-82:
1 | let foo : 'a @ nonportable contended -> (unit -> unit) @ portable = fun a () -> ()
                                                                        ^^^^^^^^^^^^^^
Error: This function when partially applied returns a value which is "nonportable",
       but expected to be "portable".
|}]

(* closing over uncontended gives nonportable *)
let foo : 'a @ uncontended portable -> (unit -> unit) @ portable = fun a () -> ()
[%%expect{|
Line 1, characters 67-81:
1 | let foo : 'a @ uncontended portable -> (unit -> unit) @ portable = fun a () -> ()
                                                                       ^^^^^^^^^^^^^^
Error: This function when partially applied returns a value which is "nonportable",
       but expected to be "portable".
|}]

(* closing over shared gives nonportable *)
let foo : 'a @ shared portable -> (unit -> unit) @ portable = fun a () -> ()
[%%expect{|
Line 1, characters 62-76:
1 | let foo : 'a @ shared portable -> (unit -> unit) @ portable = fun a () -> ()
                                                                  ^^^^^^^^^^^^^^
Error: This function when partially applied returns a value which is "nonportable",
       but expected to be "portable".
|}]
(* CR modes: These three tests are in principle fine to allow (they don't cause a data
   race), since a is never used *)

let foo : ('a @ contended portable -> (string -> string) @ portable) @ nonportable contended = fun a b -> best_bytes ()
(* CR layouts v2.8: arrows should cross contention. *)
[%%expect{|
Line 1, characters 4-119:
1 | let foo : ('a @ contended portable -> (string -> string) @ portable) @ nonportable contended = fun a b -> best_bytes ()
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error: This value is "contended" but expected to be "uncontended".
|}]

let foo : ('a @ contended portable -> (string -> string) @ portable) @ uncontended portable = fun a b -> best_bytes ()
[%%expect{|
Line 1, characters 105-115:
1 | let foo : ('a @ contended portable -> (string -> string) @ portable) @ uncontended portable = fun a b -> best_bytes ()
                                                                                                             ^^^^^^^^^^
Error: The value "best_bytes" is nonportable, so cannot be used inside a function that is portable.
|}]

(* immediates crosses portability and contention *)
let foo (x : int @ nonportable) (y : int @ contended) =
    let _ @ portable = x in
    let _ @ uncontended = y in
    let _ @ shared = y in
    ()
[%%expect{|
val foo : int -> int @ contended -> unit = <fun>
|}]

let foo (x : int @ shared) =
    let _ @ uncontended = x in
    ()
[%%expect{|
val foo : int @ shared -> unit = <fun>
|}]

(* TESTING immutable array *)
module Iarray = Stdlib_stable.Iarray

let foo (r : int iarray @ contended) = Iarray.get r 42
[%%expect{|
module Iarray = Stdlib_stable.Iarray
val foo : int iarray @ contended -> int = <fun>
|}]

let foo (r @ contended) = Iarray.get r 42
[%%expect{|
Line 1, characters 37-38:
1 | let foo (r @ contended) = Iarray.get r 42
                                         ^
Error: This value is "contended" but expected to be "uncontended".
|}]

(* CR zqian: add portable/uncontended modality and test. *)
