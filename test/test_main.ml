(* End-to-end tests of the built binary named by $OCLEAN. Skipped when unset. *)

open Harness

type outcome = { code : int; out : string; err : string }

let run ?(input = "") ~cwd args =
  match Sys.getenv_opt "OCLEAN" with
  | None -> None
  | Some binary ->
      let out = Filename.temp_file "oclean" ".out" and err = Filename.temp_file "oclean" ".err" in
      let command =
        Printf.sprintf "cd %s && printf %s | %s >%s 2>%s" (Filename.quote cwd)
          (Filename.quote input)
          (String.concat " " (List.map Filename.quote (binary :: args)))
          (Filename.quote out) (Filename.quote err)
      in
      let code = Sys.command command in
      let outcome = { code; out = read_file out; err = read_file err } in
      Sys.remove out;
      Sys.remove err;
      Some outcome

let with_run ?input ~cwd args f = Option.iter f (run ?input ~cwd args)

let tree = [ ("p/a/__pycache__/x.pyc", "1"); ("p/b.pyc", "22"); ("p/keep.py", "3") ]

let tests =
  group "Main"
    [
      it "previews without removing" (fun () ->
          with_tree tree (fun root ->
              with_run ~cwd:root [ "-p"; "p"; "-d" ] (fun r ->
                  check_int "exit" 0 r.code;
                  check_string "listing"
                    (Printf.sprintf "Matched: %s\nMatched: %s\n" (root / "p/a/__pycache__") (root / "p/b.pyc"))
                    r.out;
                  check_bool "untouched" (Sys.file_exists (root / "p/b.pyc")))));
      it "removes only after a yes" (fun () ->
          with_tree tree (fun root ->
              with_run ~input:"n\n" ~cwd:root [ "-p"; "p" ] (fun r ->
                  check_int "exit" 0 r.code;
                  check_bool "prompted" (contains ~sub:"Delete 2 item(s)? [y/N]" r.err);
                  check_bool "declined" (Sys.file_exists (root / "p/b.pyc")));
              with_run ~input:"Y\n" ~cwd:root [ "-p"; "p"; "-q" ] (fun r ->
                  check_int "exit" 0 r.code;
                  check_string "quiet" "" r.out;
                  check_bool "removed" (not (Sys.file_exists (root / "p/b.pyc")));
                  check_bool "kept" (Sys.file_exists (root / "p/keep.py")))));
      it "reports failed removals and keeps going" (fun () ->
          if not (as_root ()) then
            with_tree [ ("t/ro/__pycache__/x.pyc", "1"); ("t/rw/__pycache__/y.pyc", "2") ] (fun root ->
                Unix.chmod (root / "t/ro") 0o555;
                Fun.protect
                  ~finally:(fun () -> Unix.chmod (root / "t/ro") 0o755)
                  (fun () ->
                    with_run ~cwd:root [ "-p"; "t"; "-y"; "--format"; "json" ] (fun r ->
                        check_int "exit" 1 r.code;
                        check_bool "failure in JSON"
                          (contains ~sub:("\"failures\":[{\"path\":\"" ^ (root / "t/ro/__pycache__")) r.out);
                        check_bool "later target removed" (not (Sys.file_exists (root / "t/rw/__pycache__")))))));
      it "discovers configuration in an ancestor" (fun () ->
          with_tree [ (".oclean.toml", "patterns = [\"**/*.marker\"]\n"); ("n/d/x.marker", "") ] (fun root ->
              with_run ~cwd:(root / "n/d") [ "-c"; "-d" ] (fun r ->
                  check_string "found" (Printf.sprintf "Matched: %s\n" (root / "n/d/x.marker")) r.out)));
      it "lists the patterns a run would use" (fun () ->
          with_tree [] (fun root ->
              with_run ~cwd:root [ "-g"; "**/*.log"; "--preset"; "rust"; "-l" ] (fun r ->
                  check_string "includes and presets" "**/*.log\n**/target\n" r.out)));
      it "rejects bad input before scanning" (fun () ->
          with_tree [] (fun root ->
              with_run ~cwd:root [ "-e"; "[x" ] (fun r ->
                  check_int "exit" 1 r.code;
                  check_string "message" "oclean: invalid glob pattern: [x\n" r.err);
              with_run ~cwd:root [ "-p"; "missing" ] (fun r ->
                  check_string "message" "oclean: invalid path: missing\n" r.err)));
    ]
