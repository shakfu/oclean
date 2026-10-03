(* The oclean executable: configuration, prompting and exit codes. *)

let colored mode fd =
  Style.enabled ~mode ~no_color:(Sys.getenv_opt "NO_COLOR") ~term:(Sys.getenv_opt "TERM")
    ~tty:(Unix.isatty fd)

(* Set before argv is parsed, so a parse error can be coloured too. *)
let err_color = ref (colored Auto Unix.stderr)

let error_line msg = Style.red ~color:!err_color "oclean:" ^ " " ^ msg

let die msg =
  prerr_endline (error_line msg);
  exit 1

let ok_or_die = function Ok x -> x | Error e -> die e

let ( let* ) = Result.bind

let compile_all globs =
  List.fold_left
    (fun acc g -> Result.bind acc (fun gs -> Result.map (fun c -> c :: gs) (Glob.compile g)))
    (Ok []) globs
  |> Result.map List.rev

let rec or_list = function
  | [] -> ""
  | [ x ] -> x
  | [ x; y ] -> x ^ ", or " ^ y
  | x :: rest -> x ^ ", " ^ or_list rest

(* Checks that must pass before anything touches the file system. *)
let validate (opts : Options.t) =
  match List.find_opt (fun p -> Preset.lookup p = None) opts.presets with
  | Some bad -> Error (Printf.sprintf "unknown preset '%s' (use %s)" bad (or_list Preset.names))
  | None ->
      let* patterns = compile_all (Preset.resolve opts) in
      let* excludes = compile_all opts.excludes in
      Ok (patterns, excludes)

(* The prompt goes to stderr so stdout carries only the report. *)
let confirm (opts : Options.t) count =
  opts.assume_yes
  ||
  (flush stdout;
   Printf.eprintf "%s %!" (Style.yellow ~color:!err_color (Printf.sprintf "Delete %d item(s)? [y/N]" count));
   match In_channel.input_line stdin with
   | Some answer -> List.mem (String.lowercase_ascii (String.trim answer)) [ "y"; "yes" ]
   | None -> false)

(* Sizes are known only with --stats or JSON; measuring walks every match. *)
let measured (opts : Options.t) = opts.stats || opts.format = Json

(* [None] when nothing was attempted. Otherwise the failures and bytes freed. *)
let remove (inv : Cli.t) (opts : Options.t) (targets : Target.t list) =
  let total = List.length targets in
  if opts.dry_run || total = 0 || not (confirm opts total) then None
  else
    let total_size = List.fold_left (fun n (t : Target.t) -> n + t.size) 0 targets in
    let started = ref 0 and freed = ref 0 in
    let message _ =
      if measured opts then
        Printf.sprintf "removing, %s of %s" (Report.format_size !freed) (Report.format_size total_size)
      else Printf.sprintf "removing, %s freed" (Report.format_size !freed)
    in
    Progress.with_progress inv.progress ~message ~summary:(fun _ -> None) (fun p ->
        let on_remove (t : Target.t) =
          Progress.set_bar p !started total;
          incr started;
          if inv.verbose then Progress.note p ("removing " ^ t.path)
        in
        let failures =
          Delete.remove_all ~on_remove ~on_visit:(Progress.show p)
            ~on_freed:(fun n -> freed := !freed + n)
            targets
        in
        if inv.verbose then
          Progress.note p (Printf.sprintf "removed %d item(s)" (total - List.length failures));
        Some (failures, !freed))

let root_or_die opts =
  let dir = Options.root opts in
  if not (Sys.file_exists dir && Sys.is_directory dir) then die ("invalid path: " ^ dir);
  dir

let clean (inv : Cli.t) (opts : Options.t) patterns excludes =
  let root = Util.absolute (root_or_die opts) in
  let color = colored inv.color Unix.stdout in
  let matches = ref 0 in
  let summary =
    Progress.with_progress inv.progress
      ~message:(fun n -> Printf.sprintf "scanning, %d entries, %d matches" n !matches)
      ~summary:(fun n -> Some (Printf.sprintf "scanned %d entries" n))
      (fun p ->
        let note msg = if inv.verbose then Progress.note p msg in
        note ("root: " ^ root);
        note ("patterns: " ^ String.concat ", " (List.map Glob.source patterns));
        let on_match (t : Target.t) =
          incr matches;
          note (Printf.sprintf "match: %s (%s)" t.path (Target.label t.reason))
        in
        let targets = Scan.scan ~on_visit:(Progress.tick p) ~on_match opts ~patterns ~excludes root in
        Progress.set_message p (fun _ -> "measuring sizes");
        Report.summarize ~measure:(measured opts) ~on_visit:(Progress.show p)
          (List.sort (fun (a : Target.t) b -> String.compare a.path b.path) targets))
  in
  let failures =
    match opts.format with
    | Text -> (
        if not opts.quiet then print_string (Report.render_text ~color ~stats:opts.stats summary);
        match remove inv opts summary.targets with
        | None -> []
        | Some (failures, freed) ->
            let count = List.length summary.targets - List.length failures in
            if not opts.quiet then print_string (Report.render_removed ~color ~count ~freed ());
            List.iter (fun (f : Delete.failure) -> prerr_endline (error_line f.error)) failures;
            failures)
    | Json ->
        let failures, freed = Option.value ~default:([], 0) (remove inv opts summary.targets) in
        print_endline (Report.render_json ~dry_run:opts.dry_run ~failures ~freed summary);
        failures
  in
  if failures <> [] then exit 1

let main () =
  match Cli.parse (List.tl (Array.to_list Sys.argv)) with
  | Error e -> die e
  | Ok { command = Show_help; _ } -> print_string Cli.help
  | Ok { command = Show_version; _ } -> print_endline Cli.version
  | Ok inv -> (
      err_color := colored inv.color Unix.stderr;
      let opts = ok_or_die (Config.resolve inv.config inv.options) in
      let patterns, excludes = ok_or_die (validate opts) in
      match inv.command with
      | Write_config ->
          let file = Filename.concat (root_or_die opts) Config.file_name in
          if not (Config.write_default file) then
            die (Printf.sprintf "cannot overwrite existing '%s' file" file)
      | List_patterns -> List.iter (fun g -> print_endline (Glob.source g)) patterns
      | Clean | Show_help | Show_version -> clean inv opts patterns excludes)

let () =
  try main () with
  | Sys_error msg -> die msg
  | Unix.Unix_error (e, _, arg) -> die (arg ^ ": " ^ Unix.error_message e)
