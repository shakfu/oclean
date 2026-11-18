open Harness

let target = target_of ~reason:(Pattern "x")
let remove_all ?on_visit ?on_freed root targets = Delete.remove_all ?on_visit ?on_freed ~root (List.map target targets)
let errors = List.map (fun (f : Delete.failure) -> (f.path, f.error))
let check_errors = check ~show:(fun xs -> String.concat "; " (List.map (pair str str) xs))

let tests =
  group "Delete"
    [
      it "removes files and directory trees" (fun () ->
          with_tree [ ("d/a", "1"); ("d/e/b", "2"); ("f", "3") ] (fun root ->
              check_bool "no failures" (remove_all root [ root / "d"; root / "f" ] = []);
              check_bool "directory gone" (not (Sys.file_exists (root / "d")));
              check_bool "file gone" (not (Sys.file_exists (root / "f")))));
      it "reports every path it removes" (fun () ->
          with_tree [ ("d/a", "1"); ("d/e/b", "2") ] (fun root ->
              let visited = ref [] in
              ignore (remove_all ~on_visit:(fun p -> visited := p :: !visited) root [ root / "d" ]);
              check_strings "parent first, then children"
                [ root / "d"; root / "d/a"; root / "d/e"; root / "d/e/b" ]
                (List.sort String.compare !visited)));
      it "counts the bytes it frees" (fun () ->
          with_tree [ ("d/a", "123"); ("d/e/b", "12345"); ("f", "1") ] (fun root ->
              let freed = ref 0 in
              ignore (remove_all ~on_freed:(fun n -> freed := !freed + n) root [ root / "d"; root / "f" ]);
              check_int "file bytes only" 9 !freed));
      it "removes a symlink, not what it points to" (fun () ->
          with_tree [ ("real/keep", "1") ] (fun root ->
              Unix.symlink (root / "real") (root / "link");
              check_bool "removed" (remove_all root [ root / "link" ] = []);
              check_bool "target intact" (Sys.file_exists (root / "real/keep"))));
      it "unlinks a symlink inside a directory target without following it" (fun () ->
          with_tree [ ("real/keep", "1"); ("d/f", "2") ] (fun root ->
              Unix.symlink (root / "real") (root / "d/link");
              check_bool "removed" (remove_all root [ root / "d" ] = []);
              check_bool "gone" (not (Sys.file_exists (root / "d")));
              check_bool "link target intact" (Sys.file_exists (root / "real/keep"))));
      it "removes below a symlinked root" (fun () ->
          with_tree [ ("real/d/f", "1") ] (fun root ->
              Unix.symlink (root / "real") (root / "link");
              check_bool "removed" (remove_all (root / "link") [ root / "link/d" ] = []);
              check_bool "gone" (not (Sys.file_exists (root / "real/d")))));
      it "refuses a target replaced since the scan" (fun () ->
          with_tree [ ("t/f", "1") ] (fun root ->
              let t = target (root / "t") in
              Sys.rename (root / "t") (root / "old");
              mkdir_p (root / "t");
              write_file (root / "t/precious") "2";
              check_errors "refused" [ (root / "t", "replaced since the scan") ]
                (errors (Delete.remove_all ~root [ t ]));
              check_bool "replacement kept" (Sys.file_exists (root / "t/precious"))));
      it "does not follow a component swapped for a symlink" (fun () ->
          with_tree [ ("root/a/c/x", "1"); ("outside/c/keep", "2") ] (fun dir ->
              let root = dir / "root" in
              let t = target (root / "a/c") in
              Sys.rename (root / "a") (root / "a.moved");
              Unix.symlink (dir / "outside") (root / "a");
              let failures = Delete.remove_all ~root [ t ] in
              check_strings "failed" [ root / "a/c" ] (List.map fst (errors failures));
              check_bool "outside kept" (Sys.file_exists (dir / "outside/c/keep"))));
      it "removes read-only directories inside a target" (fun () ->
          with_tree [ ("d/a", "1"); ("d/ro/b", "22"); ("d/ro/sub/c", "333") ] (fun root ->
              List.iter (fun d -> Unix.chmod (root / d) 0o555) [ "d/ro/sub"; "d/ro"; "d" ];
              let freed = ref 0 in
              check_bool "no failures" (remove_all ~on_freed:(fun n -> freed := !freed + n) root [ root / "d" ] = []);
              check_bool "gone" (not (Sys.file_exists (root / "d")));
              check_int "bytes" 6 !freed));
      it "continues past a failed removal" (fun () ->
          if not (as_root ()) then
            with_tree [ ("ro/__pycache__/x.pyc", "1"); ("rw/__pycache__/y.pyc", "2") ] (fun root ->
                Unix.chmod (root / "ro") 0o555;
                let freed = ref 0 in
                let failures =
                  Fun.protect
                    ~finally:(fun () -> Unix.chmod (root / "ro") 0o755)
                    (fun () ->
                      remove_all ~on_freed:(fun n -> freed := !freed + n) root
                        [ root / "ro/__pycache__"; root / "rw/__pycache__" ])
                in
                check_strings "one failure" [ root / "ro/__pycache__" ]
                  (List.map (fun (f : Delete.failure) -> f.target.path) failures);
                check_errors "names the path and cause" [ (root / "ro/__pycache__", "Permission denied") ]
                  (errors failures);
                check_int "only removed bytes counted" 2 !freed;
                check_bool "later target removed" (not (Sys.file_exists (root / "rw/__pycache__")))));
      it "reports a missing path" (fun () ->
          with_tree [ ("f", "1") ] (fun root ->
              let t = target (root / "f") in
              Sys.remove (root / "f");
              check_int "error" 1 (List.length (Delete.remove_all ~root [ t ]))));
    ]
