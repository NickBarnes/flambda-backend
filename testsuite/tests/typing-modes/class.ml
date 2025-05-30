(* TEST
    expect;
*)

(* This file tests that classes/objects are sound wrt modes. *)

let unique_use : 'a @ unique -> unit = fun _ -> ()

let portable_use : 'a @ portable -> unit = fun _ -> ()
[%%expect{|
val unique_use : 'a @ unique -> unit = <fun>
val portable_use : 'a @ portable -> unit = <fun>
|}]

(* There is a closure_lock of legacy around a class. We test for comonadic and
   monadic axes separately. *)

(* class cannot refer to external local things *)
let foo () =
    let local_ s = "hello" in
    let module M = struct
    class cla = object
        val k = s
    end
    end in ()
[%%expect{|
Line 5, characters 16-17:
5 |         val k = s
                    ^
Error: The value "s" is local, so cannot be used inside a class.
|}]

(* class can refer to external unique things, but only as aliased. *)
let foo () =
    let unique_ s = "hello" in
    let module M = struct
    class cla = object
        val k = unique_use s
    end
    end in ()
[%%expect{|
Line 5, characters 27-28:
5 |         val k = unique_use s
                               ^
Error: This value is "aliased" but expected to be "unique".
  Hint: This identifier cannot be used uniquely,
  because it is defined in a class.
|}]

(* instance variables need to be defined as legacy *)
class cla = object
    val x = ("world" : _ @ local)
end
[%%expect{|
Line 2, characters 12-33:
2 |     val x = ("world" : _ @ local)
                ^^^^^^^^^^^^^^^^^^^^^
Error: This value escapes its region.
|}]

(* instance variables are available as legacy to methods *)
class cla = object
    val x = (fun y -> y : _ @ portable)

    method foo = portable_use x
end
[%%expect{|
Line 4, characters 30-31:
4 |     method foo = portable_use x
                                  ^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* values written to instance variables need to be legacy *)
class cla = object
    val mutable x = "hello"

    method foo = x <- ("world" : _ @ local)
end
[%%expect{|
Line 4, characters 22-43:
4 |     method foo = x <- ("world" : _ @ local)
                          ^^^^^^^^^^^^^^^^^^^^^
Error: This value escapes its region.
|}]

class cla = object
    method m = "hello"
end

class type cla = object
    method m : string
end

[%%expect{|
class cla : object method m : string end
class type cla = object method m : string end
|}]

(* object crosses to [global] and [many]. Below, we only demonstrate [global]. *)

(* crosses at method dispatch *)
let foo (obj @ local) =
    obj#m
[%%expect{|
val foo : local_ < m : 'a; .. > -> 'a = <fun>
|}]

(* crosses at function application *)
let foo (obj @ local) =
    ref (obj : cla)
[%%expect{|
val foo : local_ cla -> cla ref = <fun>
|}]

(* crosses at binding site. This allows the closure to be global. *)
let foo (obj : cla @ local) =
    ref (fun () -> let _ = obj in ())
[%%expect{|
val foo : local_ cla -> (unit -> unit) ref = <fun>
|}]

(* Objects don't cross monadic axes. Objects are defined at [uncontended]
    always, but that doesn't mean they cross contention. *)
let foo (obj : cla @ contended) =
    let _ @ uncontended = obj in
    ()
[%%expect{|
Line 2, characters 26-29:
2 |     let _ @ uncontended = obj in
                              ^^^
Error: This value is "contended" but expected to be "uncontended".
|}]

(* methods are available as legacy *)
let u =
    let obj = new cla in
    portable_use obj#m
[%%expect{|
Line 3, characters 17-22:
3 |     portable_use obj#m
                     ^^^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* for methods, arguments can be of any modes *)
class cla = object
    method foo (x : unit -> unit) = portable_use x
end
[%%expect{|
class cla : object method foo : (unit -> unit) @ portable -> unit end
|}]

(* the argument mode is soundly required during application *)
let foo () =
    let x @ nonportable = fun x -> x in
    let o = new cla in
    o#foo x
[%%expect{|
Line 4, characters 10-11:
4 |     o#foo x
              ^
Error: This value is "nonportable" but expected to be "portable".
|}]


(* Closing over classes affects closure's mode *)
let u =
    let foo () = new cla in
    portable_use foo
[%%expect{|
Line 3, characters 17-20:
3 |     portable_use foo
                     ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

module type SC = sig
    class cla : object end
end
[%%expect{|
module type SC = sig class cla : object  end end
|}]

let u =
    let foo () =
        let m = (module struct class cla = object end end : SC) in
        let module M = (val m) in
        new M.cla
    in
    portable_use foo
[%%expect{|
val u : unit = ()
|}]

(* objects are always legacy *)
let u =
    let obj = new cla in
    portable_use obj
[%%expect{|
Line 3, characters 17-20:
3 |     portable_use obj
                     ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

let foo () =
    let x = object end in
    portable_use x
[%%expect{|
Line 3, characters 17-18:
3 |     portable_use x
                     ^
Error: This value is "nonportable" but expected to be "portable".
|}]

class cla = object
    method m =
        let o = {< >} in
        portable_use o
end
[%%expect{|
Line 4, characters 21-22:
4 |         portable_use o
                         ^
Error: This value is "nonportable" but expected to be "portable".
|}]
