(* TEST
 flags += "-alert -do_not_spawn_domains -alert -unsafe_multidomain";
 ocamlrunparam += ",d=129";
 runtime5;
 multidomain;
 { native; }
*)

let m = Mutex.create ()

let _ =
  Mutex.lock m;
  (* The default max domains limit is 128. In this test, we make this limit 129
     and spawn 128 domains in addition to the main domain. *)
  for i = 1 to 128 do
    Domain.spawn (fun _ -> Mutex.lock m) |> ignore
  done;
  print_endline "ok"
