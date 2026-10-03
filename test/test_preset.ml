open Harness

let check_lookup = check ~show:(function None -> "None" | Some xs -> "Some " ^ strs xs)

let tests =
  group "Preset"
    [
      it "knows the documented presets" (fun () ->
          check_strings "names" [ "common"; "python"; "node"; "rust"; "java"; "c"; "go"; "all" ]
            Preset.names);
      it "looks presets up by name" (fun () ->
          check_bool "python"
            (Option.fold ~none:false ~some:(List.mem "**/__pycache__") (Preset.lookup "python"));
          check_lookup "rust" (Some [ "**/target" ]) (Preset.lookup "rust");
          check_lookup "unknown" None (Preset.lookup "nope"));
      it "keeps shell and REPL history out of every preset" (fun () ->
          check_strings "history patterns" []
            (List.filter (fun p -> contains ~sub:"history" p) (Preset.expand [ "all" ])));
      it "ignores preset name case" (fun () ->
          check_lookup "upper" (Preset.lookup "node") (Preset.lookup "NODE");
          check_lookup "mixed" (Preset.lookup "python") (Preset.lookup "Python"));
      it "expands and de-duplicates presets" (fun () ->
          let expanded = Preset.expand [ "common"; "python" ] in
          check_strings "no duplicates" (Util.dedup expanded) expanded;
          check_bool "from common" (List.mem "**/.DS_Store" expanded);
          check_bool "from python" (List.mem "**/*.pyc" expanded));
      it "includes every other preset in 'all'" (fun () ->
          let everything = Preset.expand [ "all" ] in
          check_bool "node" (List.mem "**/node_modules" everything);
          check_bool "rust" (List.mem "**/target" everything);
          check_bool "go" (List.mem "**/vendor" everything));
      it "falls back to the default patterns" (fun () ->
          check_strings "defaults" Preset.defaults (Preset.resolve Options.default));
      it "prefers explicit includes and adds presets to them" (fun () ->
          let with_globs = { Options.default with includes = [ "**/*.log" ] } in
          check_strings "includes only" [ "**/*.log" ] (Preset.resolve with_globs);
          check_strings "includes plus preset" [ "**/*.log"; "**/target" ]
            (Preset.resolve { with_globs with presets = [ "rust" ] }));
      it "uses presets alone when no includes are given" (fun () ->
          check_strings "preset only" [ "**/target" ]
            (Preset.resolve { Options.default with presets = [ "rust" ] }));
    ]
