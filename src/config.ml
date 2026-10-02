type source = No_config | Discover | File of string

type value = String of string | Bool of bool | Array of string list

let file_name = ".oclean.toml"

let default_contents = "path = \".\"\npatterns = [\"**/__pycache__\", \"**/*.pyc\"]\n"

let ( let* ) = Result.bind

(* Parse the text after '=' on one line. *)
let parse_value s =
  let n = String.length s in
  let rec skip i = if i < n && (s.[i] = ' ' || s.[i] = '\t') then skip (i + 1) else i in
  let is_quote i = i < n && (s.[i] = '"' || s.[i] = '\'') in
  (* Basic ("...") strings take escapes; literal ('...') strings do not. *)
  let string_at i =
    let quote = s.[i] in
    let b = Buffer.create 16 in
    let rec go j =
      if j >= n then Error "unterminated string"
      else if s.[j] = quote then Ok (Buffer.contents b, j + 1)
      else if s.[j] = '\\' && quote = '"' && j + 1 < n then (
        match s.[j + 1] with
        | ('"' | '\\') as c -> Buffer.add_char b c; go (j + 2)
        | 'n' -> Buffer.add_char b '\n'; go (j + 2)
        | 't' -> Buffer.add_char b '\t'; go (j + 2)
        | 'r' -> Buffer.add_char b '\r'; go (j + 2)
        | c -> Error (Printf.sprintf "unsupported escape \\%c" c))
      else (
        Buffer.add_char b s.[j];
        go (j + 1))
    in
    go (i + 1)
  in
  let finished i =
    let i = skip i in
    if i = n || s.[i] = '#' then Ok () else Error "unexpected text after value"
  in
  let rec items acc i =
    let i = skip i in
    if i < n && s.[i] = ']' then Ok (List.rev acc, i + 1)
    else if is_quote i then
      let* item, j = string_at i in
      let j = skip j in
      if j < n && s.[j] = ',' then items (item :: acc) (j + 1)
      else if j < n && s.[j] = ']' then Ok (List.rev (item :: acc), j + 1)
      else Error "expected , or ] in array"
    else Error "array items must be strings"
  in
  let i = skip 0 in
  if is_quote i then
    let* v, j = string_at i in
    let* () = finished j in
    Ok (String v)
  else if i < n && s.[i] = '[' then
    let* v, j = items [] (i + 1) in
    let* () = finished j in
    Ok (Array v)
  else
    let word = match String.index_opt s '#' with Some k -> String.sub s 0 k | None -> s in
    match String.trim word with
    | "true" -> Ok (Bool true)
    | "false" -> Ok (Bool false)
    | _ -> Error "expected a string, boolean or array"

let parse text =
  let rec go acc lineno = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        let line = String.trim line in
        if line = "" || line.[0] = '#' then go acc (lineno + 1) rest
        else if line.[0] = '[' then Ok (List.rev acc)
        else
          match String.index_opt line '=' with
          | None -> Error (Printf.sprintf "line %d: expected key = value" lineno)
          | Some i -> (
              let key = String.trim (String.sub line 0 i) in
              match parse_value (String.sub line (i + 1) (String.length line - i - 1)) with
              | Ok v -> go ((key, v) :: acc) (lineno + 1) rest
              | Error e -> Error (Printf.sprintf "line %d: %s" lineno e)))
  in
  go [] 1 (String.split_on_char '\n' text)

let merge file entries (o : Options.t) =
  let get key kind extract =
    match List.assoc_opt key entries with
    | None -> Ok None
    | Some v -> (
        match extract v with
        | Some x -> Ok (Some x)
        | None -> Error (Printf.sprintf "%s: %s must be %s" file key kind))
  in
  let str key = get key "a string" (function String s -> Some s | _ -> None) in
  let arr key = get key "an array of strings" (function Array a -> Some a | _ -> None) in
  let flag key =
    Result.map (Option.value ~default:false) (get key "a boolean" (function Bool b -> Some b | _ -> None))
  in
  let keep cli file = match cli, file with [], Some xs -> xs | _ -> cli in
  let* path = str "path" in
  let* patterns = arr "patterns" in
  let* excludes = arr "exclude_patterns" in
  let* presets = arr "presets" in
  let* dry_run = flag "dry_run" in
  let* assume_yes = flag "skip_confirmation" in
  let* stats = flag "stats_mode" in
  let* symlinks = flag "include_symlinks" in
  let* broken_symlinks = flag "remove_broken_symlinks" in
  let* artifacts = flag "build_artifacts" in
  Ok
    {
      o with
      root = (if o.root = None then path else o.root);
      includes = keep o.includes patterns;
      excludes = keep o.excludes excludes;
      presets = keep o.presets presets;
      dry_run = o.dry_run || dry_run;
      assume_yes = o.assume_yes || assume_yes;
      stats = o.stats || stats;
      symlinks = o.symlinks || symlinks;
      broken_symlinks = o.broken_symlinks || broken_symlinks;
      artifacts = o.artifacts || artifacts;
    }

let apply file o =
  let* text = try Ok (In_channel.with_open_bin file In_channel.input_all) with Sys_error e -> Error e in
  let* entries = Result.map_error (fun e -> file ^ ": " ^ e) (parse text) in
  merge file entries o

let discover start =
  let rec climb dir =
    let candidate = Filename.concat dir file_name in
    if Util.is_file candidate then Some candidate
    else
      let parent = Filename.dirname dir in
      if parent = dir then None else climb parent
  in
  let global home =
    let p = List.fold_left Filename.concat home [ ".config"; "oclean"; "config.toml" ] in
    if Util.is_file p then Some p else None
  in
  match climb (Util.absolute start) with
  | Some _ as found -> found
  | None -> Option.bind (Sys.getenv_opt "HOME") global

let resolve source o =
  match source with
  | No_config -> Ok o
  | File f -> apply f o
  | Discover -> (
      match discover (Sys.getcwd ()) with Some f -> apply f o | None -> Ok o)

let write_default path =
  match Unix.openfile path [ O_WRONLY; O_CREAT; O_EXCL ] 0o644 with
  | exception Unix.Unix_error (EEXIST, _, _) -> false
  | fd ->
      let oc = Unix.out_channel_of_descr fd in
      Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc default_contents);
      true
