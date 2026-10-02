open Harness

let config_text =
  String.concat "\n"
    [
      "path = \"/srv/project\"";
      "patterns = [\"**/*.log\", \"**/*.tmp\"]";
      "exclude_patterns = [\"**/keep\"]";
      "presets = [\"rust\", \"go\"]";
      "dry_run = true";
      "skip_confirmation = true";
      "stats_mode = true";
      "include_symlinks = true";
      "remove_broken_symlinks = true";
      "build_artifacts = true";
      "";
    ]

let defaults = Options.default

let apply file o =
  match Config.apply file o with Ok o -> o | Error e -> fail "unexpected error: %s" e

let apply_error file o =
  match Config.apply file o with Ok _ -> fail "expected an error" | Error e -> e

let with_config text f = with_tree [ (".oclean.toml", text) ] (fun root -> f (root / ".oclean.toml"))
let check_root = check ~show:(function None -> "None" | Some s -> str s)

let tests =
  group "Config"
    [
      it "reads every supported key" (fun () ->
          with_config config_text (fun file ->
              let o = apply file defaults in
              check_root "path" (Some "/srv/project") o.root;
              check_strings "patterns" [ "**/*.log"; "**/*.tmp" ] o.includes;
              check_strings "excludes" [ "**/keep" ] o.excludes;
              check_strings "presets" [ "rust"; "go" ] o.presets;
              check_bool "dry run" o.dry_run;
              check_bool "skip confirmation" o.assume_yes;
              check_bool "stats" o.stats;
              check_bool "symlinks" o.symlinks;
              check_bool "broken symlinks" o.broken_symlinks;
              check_bool "artifacts" o.artifacts));
      it "strips quotes from string values" (fun () ->
          with_config "path = \".\"\n" (fun file -> check_root "unquoted" (Some ".") (apply file defaults).root);
          with_config "path = 'a\\b'\n" (fun file ->
              check_root "literal string" (Some "a\\b") (apply file defaults).root));
      it "ignores comments" (fun () ->
          with_config "# heading\npath = \".\" # trailing\npatterns = [\"a#b\"] # x\ndry_run = true # y\n"
            (fun file ->
              let o = apply file defaults in
              check_root "path" (Some ".") o.root;
              check_strings "hash inside a string" [ "a#b" ] o.includes;
              check_bool "flag" o.dry_run));
      it "matches keys exactly, not by prefix" (fun () ->
          with_config "path_style = \"x\"\n" (fun file -> check_root "unset" None (apply file defaults).root));
      it "stops at the first table header" (fun () ->
          with_config "dry_run = true\n[other]\npath = \"x\"\n" (fun file ->
              let o = apply file defaults in
              check_root "table key ignored" None o.root;
              check_bool "top level read" o.dry_run));
      it "rejects values of the wrong type" (fun () ->
          with_config "dry_run = \"yes\"\n" (fun file ->
              check_string "message" (file ^ ": dry_run must be a boolean") (apply_error file defaults));
          with_config "path = .\n" (fun file ->
              check_string "bare word" (file ^ ": line 1: expected a string, boolean or array")
                (apply_error file defaults)));
      it "lets command line lists and path win over the file" (fun () ->
          with_config config_text (fun file ->
              let o =
                apply file { defaults with root = Some "here"; includes = [ "**/*.bak" ]; presets = [ "node" ] }
              in
              check_root "path" (Some "here") o.root;
              check_strings "patterns" [ "**/*.bak" ] o.includes;
              check_strings "presets" [ "node" ] o.presets));
      it "treats absent flags as off and never turns one off" (fun () ->
          with_config "dry_run = false\n" (fun file ->
              check_bool "still on" (apply file { defaults with dry_run = true }).dry_run;
              check_bool "off" (not (apply file defaults).dry_run)));
      it "finds the nearest config file walking upwards" (fun () ->
          with_tree [ (".oclean.toml", "path = \".\"\n"); ("a/b/c/", "") ] (fun root ->
              check ~show:(Option.fold ~none:"None" ~some:str) "ancestor"
                (Some (root / ".oclean.toml"))
                (Config.discover (root / "a/b/c"))));
      it "prefers the closest config file" (fun () ->
          with_tree [ (".oclean.toml", ""); ("a/.oclean.toml", ""); ("a/b/", "") ] (fun root ->
              check ~show:(Option.fold ~none:"None" ~some:str) "closest"
                (Some (root / "a/.oclean.toml"))
                (Config.discover (root / "a/b"))));
      it "discovers from the working directory" (fun () ->
          with_tree [ (".oclean.toml", "dry_run = true\n"); ("a/b/", "") ] (fun root ->
              in_directory (root / "a/b") (fun () ->
                  match Config.resolve Discover defaults with
                  | Ok o -> check_bool "found in an ancestor" o.dry_run
                  | Error e -> fail "%s" e)));
      it "writes a starter config and refuses to overwrite" (fun () ->
          with_tree [] (fun root ->
              in_directory root (fun () ->
                  check_bool "written" (Config.write_default Config.file_name);
                  check_string "contents" Config.default_contents (read_file Config.file_name);
                  check_bool "parses" (Result.is_ok (Config.apply Config.file_name defaults));
                  check_bool "refused" (not (Config.write_default Config.file_name)))));
      it "resolves the requested source" (fun () ->
          with_config "dry_run = true\n" (fun file ->
              check_bool "no config" (Config.resolve No_config defaults = Ok defaults);
              check_bool "explicit file" ((Result.get_ok (Config.resolve (File file) defaults)).dry_run);
              check_bool "missing file" (Result.is_error (Config.resolve (File (file ^ ".nope")) defaults))));
    ]
