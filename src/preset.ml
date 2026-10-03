let table =
  [
    ( "common",
      [ "**/.DS_Store"; "**/Thumbs.db"; "**/*.swp"; "**/*.swo" ] );
    ( "python",
      [ "**/__pycache__"; "**/.coverage"; "**/.mypy_cache"; "**/.pylint_cache";
        "**/.pytest_cache"; "**/.ruff_cache"; "**/.rumdl_cache"; "**/.pyscn";
        "**/.ropeproject"; "**/pip-log.txt"; "**/*.pyc"; "**/*.pyo" ] );
    ( "node",
      [ "**/node_modules"; "**/.next"; "**/.nuxt"; "**/.cache"; "**/dist"; "**/.parcel-cache";
        "**/.turbo"; "**/.eslintcache"; "**/coverage"; "**/.nyc_output" ] );
    ("rust", [ "**/target" ]);
    ( "java",
      [ "**/*.class"; "**/target"; "**/.gradle"; "**/build"; "**/.settings"; "**/.classpath";
        "**/.project" ] );
    ("c", [ "**/*.o"; "**/*.obj"; "**/*.a"; "**/*.lib"; "**/*.so"; "**/*.dylib"; "**/*.dll" ]);
    ("go", [ "**/vendor" ]);
  ]

let names = List.map fst table @ [ "all" ]

let rec lookup name =
  match String.lowercase_ascii name with
  | "all" -> Some (expand (List.map fst table))
  | key -> List.assoc_opt key table

and expand presets =
  Util.dedup (List.concat_map (fun p -> Option.value (lookup p) ~default:[]) presets)

let defaults = expand [ "common"; "python" ]

let protected = [ ".git"; ".hg"; ".svn"; ".config"; ".ssh"; ".gnupg" ]

let resolve (o : Options.t) =
  match o.includes, o.presets with
  | [], [] -> defaults
  | includes, presets -> includes @ expand presets
