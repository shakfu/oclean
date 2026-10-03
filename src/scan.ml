let markers =
  [
    ( "build",
      [ "CMakeLists.txt"; "meson.build"; "package.json"; "build.gradle"; "build.gradle.kts";
        "pyproject.toml"; "setup.py"; "pubspec.yaml" ] );
    ("dist", [ "package.json"; "pyproject.toml"; "setup.py" ]);
    ("target", [ "Cargo.toml"; "pom.xml" ]);
    (".next", [ "package.json" ]);
    (".nuxt", [ "package.json" ]);
    (".svelte-kit", [ "package.json" ]);
    (".turbo", [ "package.json" ]);
    (".parcel-cache", [ "package.json" ]);
    (".gradle", [ "build.gradle"; "build.gradle.kts" ]);
    ("zig-out", [ "build.zig" ]);
    ("zig-cache", [ "build.zig" ]);
    (".zig-cache", [ "build.zig" ]);
    (".build", [ "Package.swift" ]);
    ("_build", [ "mix.exs" ]);
  ]

let is_build_artifact dir name =
  match List.assoc_opt name markers with
  | None -> false
  | Some files ->
      List.exists (fun f -> Util.is_file (Filename.concat dir f)) files
      && List.exists (fun d -> Sys.file_exists (Filename.concat d ".git")) (Util.ancestors_below_home dir)

let lstat path = try Some (Unix.lstat path) with Unix.Unix_error _ -> None

let entries dir =
  let names = try Sys.readdir dir with Sys_error _ -> [||] in
  Array.sort String.compare names;
  names

let scan ?(on_visit = ignore) ?(on_match = ignore) (o : Options.t) ~patterns ~excludes root =
  let now = Unix.time () in
  let old (st : Unix.stats) =
    match o.older_than with None -> true | Some n -> now -. st.st_mtime >= float_of_int n
  in
  let excluded rel = List.exists (fun g -> Glob.matches_path g rel) excludes in
  let protected name = (not o.no_protect) && List.mem name Preset.protected in
  let rec walk acc dir rel_dir =
    Array.fold_left (fun acc name -> visit acc dir rel_dir name) acc (entries dir)
  and visit acc dir rel_dir name =
    let path = Filename.concat dir name in
    let rel = if rel_dir = "" then name else rel_dir ^ "/" ^ name in
    let segments = Glob.path rel in
    on_visit path;
    match lstat path with
    | None -> acc
    | Some _ when excluded segments || protected name -> acc
    | Some st -> (
        let found reason size =
          let t = { Target.path; is_dir = st.st_kind = S_DIR; reason; size } in
          on_match t;
          t :: acc
        in
        match st.st_kind with
        | S_LNK when not (o.symlinks || o.broken_symlinks) -> acc
        | S_LNK when o.broken_symlinks && not (Sys.file_exists path) ->
            if old st then found Broken_symlink st.st_size else acc
        | kind -> (
            let is_dir = kind = S_DIR in
            let reason =
              if not (old st) then None
              else if o.artifacts && is_dir && is_build_artifact dir name then
                Some Target.Build_artifact
              else
                List.find_opt (fun g -> Glob.matches_path g segments) patterns
                |> Option.map (fun g -> Target.Pattern (Glob.source g))
            in
            match reason with
            | Some r when kind <> S_LNK || o.symlinks -> found r (if is_dir then 0 else st.st_size)
            | _ when is_dir -> walk acc path rel
            | _ -> acc))
  in
  List.rev (walk [] root "")

let rec directory_size ?(on_visit = ignore) path =
  Array.fold_left
    (fun total name ->
      let child = Filename.concat path name in
      on_visit child;
      match lstat child with
      | None -> total
      | Some { st_kind = S_DIR; _ } -> total + directory_size ~on_visit child
      | Some st -> total + st.st_size)
    0 (entries path)
