open Harness

let relative root path =
  let n = String.length root + 1 in
  String.sub path n (String.length path - n)

let scan ?on_visit ?on_match (o : Options.t) root patterns =
  Scan.scan ?on_visit ?on_match o ~patterns:(globs patterns) ~excludes:(globs o.excludes) root

(* Scan [root] and return the matches as sorted (relative path, reason) pairs. *)
let matches o root patterns =
  scan o root patterns
  |> List.map (fun (t : Target.t) -> (relative root t.path, Target.label t.reason))
  |> List.sort compare

let check_matches = check ~show:(fun xs -> String.concat "; " (List.map (pair str str) xs))

let project =
  [
    ("proj/__pycache__/a.pyc", "0123456789");
    ("proj/sub/__pycache__/b.pyc", "01234");
    ("proj/sub/keep.py", "x");
    ("proj/.git/config", "x");
    ("proj/.git/__pycache__/c.pyc", "x");
    ("proj/package.json", "{}");
    ("proj/dist/bundle.js", "xx");
  ]

let caches = [ ("proj/__pycache__", "**/__pycache__"); ("proj/sub/__pycache__", "**/__pycache__") ]
let defaults = Options.default

let tests =
  group "Scan"
    [
      it "matches files and directories anywhere in the tree" (fun () ->
          with_tree project (fun root ->
              check_matches "pycache" caches (matches defaults root [ "**/__pycache__" ])));
      it "matches against paths relative to a relative root" (fun () ->
          with_tree project (fun root ->
              in_directory (root / "proj") (fun () ->
                  check_strings "anchored to the root" [ "./sub/keep.py" ]
                    (List.map (fun (t : Target.t) -> t.path) (scan defaults "." [ "sub/*.py" ])))));
      it "does not descend into a directory it already matched" (fun () ->
          with_tree project (fun root ->
              check_matches "directory only, not its contents" caches
                (matches defaults root [ "**/__pycache__"; "**/*.pyc" ])));
      it "never enters protected directories" (fun () ->
          with_tree project (fun root ->
              check_matches "only the two caches" caches
                (matches defaults root [ "**/config"; "**/__pycache__" ])));
      it "enters protected directories when protection is disabled" (fun () ->
          with_tree project (fun root ->
              let found = matches { defaults with no_protect = true } root [ "**/__pycache__" ] in
              check_bool "git cache found" (List.mem ("proj/.git/__pycache__", "**/__pycache__") found)));
      it "prunes excluded paths" (fun () ->
          with_tree project (fun root ->
              check_matches "sub excluded" [ ("proj/__pycache__", "**/__pycache__") ]
                (matches { defaults with excludes = [ "**/sub" ] } root [ "**/__pycache__" ])));
      it "reports the first pattern that matched" (fun () ->
          with_tree project (fun root ->
              check_matches "first wins" caches
                (matches defaults root [ "**/__pycache__"; "__pycache__" ])));
      it "records sizes for files and zero for directories" (fun () ->
          with_tree project (fun root ->
              let sizes ts = List.map (fun (t : Target.t) -> t.size) ts in
              let show xs = String.concat "," (List.map string_of_int xs) in
              check ~show "directories are sized later" [ 0; 0 ]
                (sizes (scan defaults root [ "**/*.pyc"; "**/__pycache__" ]));
              check ~show "file size" [ 10 ] (sizes (scan defaults root [ "**/a.pyc" ]));
              check_bool "is a directory"
                (List.for_all (fun (t : Target.t) -> t.is_dir) (scan defaults root [ "**/__pycache__" ]))));
      it "only matches entries older than the age limit" (fun () ->
          with_tree project (fun root ->
              Unix.utimes (root / "proj/sub/__pycache__") 1000000. 1000000.;
              check_matches "old one only" [ ("proj/sub/__pycache__", "**/__pycache__") ]
                (matches { defaults with older_than = Some 3600 } root [ "**/__pycache__" ])));
      it "ignores symlinks unless asked" (fun () ->
          with_tree project (fun root ->
              Unix.symlink (root / "proj/sub/keep.py") (root / "proj/link.py");
              check_matches "skipped" [] (matches defaults root [ "**/link.py" ]);
              check_matches "included" [ ("proj/link.py", "**/link.py") ]
                (matches { defaults with symlinks = true } root [ "**/link.py" ])));
      it "removes broken symlinks on request" (fun () ->
          with_tree project (fun root ->
              Unix.symlink (root / "proj/nowhere") (root / "proj/dangling");
              Unix.symlink (root / "proj/package.json") (root / "proj/intact");
              check_matches "only the dangling one" [ ("proj/dangling", "broken-symlink") ]
                (matches { defaults with broken_symlinks = true } root [ "**/nothing" ])));
      it "applies the age limit to broken symlinks" (fun () ->
          with_tree project (fun root ->
              Unix.symlink (root / "proj/nowhere") (root / "proj/dangling");
              check_matches "too new" []
                (matches { defaults with broken_symlinks = true; older_than = Some 3600 } root
                   [ "**/nothing" ])));
      it "detects build artifacts next to a project marker" (fun () ->
          with_tree (project @ [ ("proj/.git/HEAD", "ref"); ("plain/dist/x.js", "x") ]) (fun root ->
              check_matches "dist only inside the repo" [ ("proj/dist", "build-artifact") ]
                (matches { defaults with artifacts = true } root [ "**/nothing" ])));
      it "requires the marker file, not just a repository" (fun () ->
          with_tree [ ("proj/.git/HEAD", "ref"); ("proj/target/x.o", "x") ] (fun root ->
              check_matches "no Cargo.toml, no match" []
                (matches { defaults with artifacts = true } root [ "**/nothing" ])));
      it "finds build artifacts of workspace members" (fun () ->
          with_tree
            [ ("ws/.git/HEAD", "ref"); ("ws/Cargo.toml", ""); ("ws/target/x", "");
              ("ws/crates/foo/Cargo.toml", ""); ("ws/crates/foo/target/x", "") ]
            (fun root ->
              check_matches "both targets"
                [ ("ws/crates/foo/target", "build-artifact"); ("ws/target", "build-artifact") ]
                (matches { defaults with artifacts = true } root [ "**/nothing" ])));
      it "terminates on symlink loops" (fun () ->
          with_tree [ ("a/b/x.pyc", "1") ] (fun root ->
              Unix.symlink (root / "a") (root / "a/b/loop");
              check_matches "loop is not followed" [ ("a/b/x.pyc", "**/*.pyc") ]
                (matches { defaults with symlinks = true } root [ "**/*.pyc" ])));
      it "reports visits and matches to the hooks" (fun () ->
          with_tree [ ("a/x.pyc", "1"); ("a/y.txt", "2") ] (fun root ->
              let visited = ref [] and matched = ref [] in
              ignore
                (scan
                   ~on_visit:(fun p -> visited := relative root p :: !visited)
                   ~on_match:(fun t -> matched := Target.label t.reason :: !matched)
                   defaults root [ "**/*.pyc" ]);
              check_strings "every entry" [ "a"; "a/x.pyc"; "a/y.txt" ] (List.rev !visited);
              check_strings "only matches" [ "**/*.pyc" ] (List.rev !matched)));
      it "measures directory trees" (fun () ->
          with_tree [ ("d/a", "12345"); ("d/e/b", "123"); ("d/e/f/c", "1") ] (fun root ->
              check_int "recursive size" 9 (Scan.directory_size (root / "d"))));
      it "survives unreadable directories" (fun () ->
          with_tree [ ("a/x.pyc", "1") ] (fun root ->
              check_int "missing directory is empty" 0 (Scan.directory_size (root / "nope"))));
    ]
