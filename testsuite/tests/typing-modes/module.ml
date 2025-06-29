(* TEST
    flags+="-extension mode";
   expect;
*)

(* This file tests the legacy aspect of modules. The non-legacy aspects are
   tested in [val_modalities.ml]. As we enrich modules with modes, this file
   will shrink. *)

let portable_use : 'a @ portable -> unit = fun _ -> ()

module type S = sig val x : 'a -> unit end

module type SL = sig type 'a t end

module M = struct
    type 'a t = int
    let x _ = ()
end
module F (X : S) = struct
    type t = int
    let x = X.x
end
[%%expect{|
val portable_use : 'a @ portable -> unit = <fun>
module type S = sig val x : 'a -> unit end
module type SL = sig type 'a t end
module M : sig type 'a t = int val x : 'a -> unit end
module F : functor (X : S) -> sig type t = int val x : 'a -> unit end
|}]

let u =
    let foo () =
        let module X = struct
            let x _ = ()
        end
        in
        let module R = F(X) in
        ()
    in
    portable_use foo
[%%expect{|
Line 10, characters 17-20:
10 |     portable_use foo
                      ^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

let u =
    let foo () =
        let m = (module struct let x _ = () end : S) in
        let module M = (val m) in
        M.x
    in
    portable_use foo
[%%expect{|
val u : unit = ()
|}]

(* first class modules are produced at legacy *)
let x = ((module M : SL) : _ @ portable)
[%%expect{|
Line 1, characters 9-24:
1 | let x = ((module M : SL) : _ @ portable)
             ^^^^^^^^^^^^^^^
Error: This value is "nonportable" but expected to be "portable".
|}]

(* first class modules are consumed at legacy *)
let foo () =
    let m @ local = (module M : SL) in
    let module M = (val m) in
    ()
[%%expect{|
Line 3, characters 24-25:
3 |     let module M = (val m) in
                            ^
Error: This value escapes its region.
|}]

let foo () =
    let bar () =
        let _ : F(M).t = 42 in
        ()
    in
    let _ = (bar : _ @ portable) in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

let foo () =
    let bar () =
        let module _ : sig
            open M
        end = struct end
        in
        ()
    in
    let _ = (bar : _ @ portable) in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

let foo () =
    let bar () =
        let module _ : (sig
            module M' : sig  end
        end with module M' := M) = struct
        end
        in
        ()
    in
    let _ = (bar : _ @ portable) in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

(* Replacing [:=] in the above example with [=] should work similarly, but I
   couldn't construct an example to test this properly. *)

let foo () =
    let bar () =
        let module _ : module type of M = struct
            type 'a t = int
            let x _ = ()
        end
        in
        ()
    in
    let _ = (bar : _ @ portable) in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

let foo () =
    let bar () =
        let module _ : (sig
            module M' := M
        end) = struct
        end
        in
        ()
    in
    let _ = (bar : _ @ portable) in
    ()
[%%expect{|
val foo : unit -> unit = <fun>
|}]

(* Pmty_alias is not testable *)

(* module alias *)
module type S = sig
    val foo : 'a -> 'a
    val baz : 'a -> 'a @@ portable
end

module M : S = struct
    let foo = fun x -> x
    let baz = fun x -> x
end
[%%expect{|
module type S = sig val foo : 'a -> 'a val baz : 'a -> 'a @@ portable end
module M : S
|}]

let (bar @ portable) () =
    let module N = M in
    M.baz ();
    N.baz ()
[%%expect{|
val bar : unit -> unit = <fun>
|}]

let (bar @ portable) () =
    let module N = M in
    N.foo ()
[%%expect{|
Line 3, characters 4-9:
3 |     N.foo ()
        ^^^^^
Error: The value "N.foo" is nonportable, so cannot be used inside a function that is portable.
|}]

let (bar @ portable) () =
    let module N = M in
    M.foo ()
[%%expect{|
Line 3, characters 4-9:
3 |     M.foo ()
        ^^^^^
Error: The value "M.foo" is nonportable, so cannot be used inside a function that is portable.
|}]

(* chained aliases. Creating alias of alias is fine. *)
let (bar @ portable) () =
    let module N = M in
    let module N' = N in
    M.baz ();
    N.baz ();
    N'.baz ()
[%%expect{|
val bar : unit -> unit = <fun>
|}]

(* locks are accumulated and not lost *)
let (bar @ portable) () =
    let module N = M in
    let module N' = N in
    N'.foo ()
[%%expect{|
Line 4, characters 4-10:
4 |     N'.foo ()
        ^^^^^^
Error: The value "N'.foo" is nonportable, so cannot be used inside a function that is portable.
|}]

(* module aliases in structures still walk locks. *)
let (bar @ portable) () =
    let module N = struct
        module L = M
    end in
    N.L.foo ()
[%%expect{|
Line 3, characters 19-20:
3 |         module L = M
                       ^
Error: "M" is a module, and modules are always nonportable, so cannot be used inside a function that is portable.
|}]

let use_unique : 'a @ unique -> unit = fun _ -> ()

(* Functors are [many], and can't close over unique values*)

let foo (x @ unique) =
  let module Foo (_ : sig end) = struct
    let () = use_unique x
  end in
  let module _ = Foo(struct end) in
  ()
[%%expect{|
val use_unique : 'a @ unique -> unit = <fun>
Line 7, characters 24-25:
7 |     let () = use_unique x
                            ^
Error: This value is "aliased" but expected to be "unique".
|}]

let foo (x @ unique) =
  let module Foo () = struct
    let () = use_unique x
  end in
  let module _ = Foo() in
  ()
[%%expect{|
Line 3, characters 24-25:
3 |     let () = use_unique x
                            ^
Error: This value is "aliased" but expected to be "unique".
|}]
