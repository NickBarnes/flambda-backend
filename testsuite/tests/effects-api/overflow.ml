(* TEST
 include stdlib_alpha;
 runtime5;
 { bytecode; }
 { native; }
*)

module Effect = Stdlib_alpha.Effect

type 'a op = E : unit op

module Eff = Effect.Make(struct
  type 'a t = 'a op
end)

let f a b c d e f g h =
   let bb = b + b in
   let bbb = bb + b in
   let cc = c + c in
   let ccc = cc + c in
   let dd = d + d in
   let ddd = dd + d in
   let ee = e + e in
   let eee = ee + e in
   let ff = f + f in
   let fff = ff + f in
   let gg = g + g in
   let ggg = gg + g in
   let hh = h + h in
   let hhh = hh + h in
   min 20 a +
     b + bb + bbb +
     c + cc + ccc +
     d + dd + ddd +
     e + ee + eee +
     f + ff + fff +
     g + gg + ggg +
     h + hh + hhh

let () =
  let rec handle = function
    | Eff.Value n -> Printf.printf "%d\n" n
    | Eff.Exception e -> raise e
    | Eff.Operation(E, _) -> assert false
  in
  handle (Eff.run (fun _ -> f 1 2 3 4 5 6 7 8))
