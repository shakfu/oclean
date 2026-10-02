open Harness

let target path = { Target.path; is_dir = false; reason = Pattern "x"; size = 0 }

let tests =
  group "Delete"
    [
      it "removes files and directory trees" (fun () ->
          with_tree [ ("d/a", "1"); ("d/e/b", "2"); ("f", "3") ] (fun root ->
              check_bool "no failures" (Delete.remove_all [ target (root / "d"); target (root / "f") ] = []);
              check_bool "directory gone" (not (Sys.file_exists (root / "d")));
              check_bool "file gone" (not (Sys.file_exists (root / "f")))));
      it "reports every path it removes" (fun () ->
          with_tree [ ("d/a", "1"); ("d/e/b", "2") ] (fun root ->
              let visited = ref [] in
              ignore (Delete.remove_all ~on_visit:(fun p -> visited := p :: !visited) [ target (root / "d") ]);
              check_strings "parent first, then children"
                [ root / "d"; root / "d/a"; root / "d/e"; root / "d/e/b" ]
                (List.sort String.compare !visited)));
      it "removes a symlink, not what it points to" (fun () ->
          with_tree [ ("real/keep", "1") ] (fun root ->
              Unix.symlink (root / "real") (root / "link");
              check_bool "removed" (Delete.remove (root / "link") = Ok ());
              check_bool "target intact" (Sys.file_exists (root / "real/keep"))));
      it "continues past a failed removal" (fun () ->
          if not (as_root ()) then
            with_tree [ ("ro/__pycache__/x.pyc", "1"); ("rw/__pycache__/y.pyc", "2") ] (fun root ->
                Unix.chmod (root / "ro") 0o555;
                let failures =
                  Fun.protect
                    ~finally:(fun () -> Unix.chmod (root / "ro") 0o755)
                    (fun () ->
                      Delete.remove_all [ target (root / "ro/__pycache__"); target (root / "rw/__pycache__") ])
                in
                check_strings "one failure" [ root / "ro/__pycache__" ]
                  (List.map (fun (f : Delete.failure) -> f.target.path) failures);
                check_bool "names the cause"
                  (List.for_all (fun (f : Delete.failure) -> contains ~sub:"Permission denied" f.error) failures);
                check_bool "later target removed" (not (Sys.file_exists (root / "rw/__pycache__")))));
      it "reports a missing path" (fun () ->
          with_tree [] (fun root -> check_bool "error" (Result.is_error (Delete.remove (root / "nope")))));
    ]
