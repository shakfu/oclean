(* The oclean executable: configuration, prompting and exit codes. *)

let die msg =
  prerr_endline ("oclean: " ^ msg);
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
   Printf.eprintf "Delete %d item(s)? [y/N] %!" count;
   match In_channel.input_line stdin with
   | Some answer -> List.mem (String.lowercase_ascii (String.trim answer)) [ "y"; "yes" ]
   | None -> false)

let remove (inv : Cli.t) (opts : Options.t) (targets : Target.t list) =
  let total = List.length targets in
  if opts.dry_run || total = 0 || not (confirm opts total) then []
  else
    Progress.with_progress inv.progress
      ~message:(fun n -> Printf.sprintf "removing, %d of %d" n total)
      ~summary:(fun _ -> None)
      (fun p ->
        let on_remove (t : Target.t) =
          Progress.tick p t.path;
          if inv.verbose then Progress.note p ("removing " ^ t.path)
        in
        let failures = Delete.remove_all ~on_remove targets in
        if inv.verbose then
          Progress.note p (Printf.sprintf "removed %d item(s)" (total - List.length failures));
        failures)

let clean (inv : Cli.t) (opts : Options.t) patterns excludes =
  let dir = Options.root opts in
  if not (Sys.file_exists dir && Sys.is_directory dir) then die ("invalid path: " ^ dir);
  let root = Util.absolute dir in
  let summary =
    Progress.with_progress inv.progress
      ~message:(Printf.sprintf "scanning, %d entries")
      ~summary:(fun n -> Some (Printf.sprintf "scanned %d entries" n))
      (fun p ->
        let note msg = if inv.verbose then Progress.note p msg in
        note ("root: " ^ root);
        note ("patterns: " ^ String.concat ", " (List.map Glob.source patterns));
        let on_match (t : Target.t) =
          note (Printf.sprintf "match: %s (%s)" t.path (Target.label t.reason))
        in
        let targets = Scan.scan ~on_visit:(Progress.tick p) ~on_match opts ~patterns ~excludes root in
        Progress.set_message p (fun _ -> "measuring sizes");
        (* Sizes are printed only with --stats or JSON; measuring walks every match. *)
        Report.summarize
          ~measure:(opts.stats || opts.format = Json)
          ~on_visit:(Progress.show p)
          (List.sort (fun (a : Target.t) b -> String.compare a.path b.path) targets))
  in
  let failures =
    match opts.format with
    | Text ->
        if not opts.quiet then print_string (Report.render_text ~stats:opts.stats summary);
        let failures = remove inv opts summary.targets in
        List.iter (fun (f : Delete.failure) -> prerr_endline ("oclean: " ^ f.error)) failures;
        failures
    | Json ->
        let failures = remove inv opts summary.targets in
        print_endline (Report.render_json ~dry_run:opts.dry_run ~failures summary);
        failures
  in
  if failures <> [] then exit 1

let main () =
  match Cli.parse (List.tl (Array.to_list Sys.argv)) with
  | Error e -> die e
  | Ok { command = Show_help; _ } -> print_string Cli.help
  | Ok { command = Show_version; _ } -> print_endline Cli.version
  | Ok inv -> (
      let opts = ok_or_die (Config.resolve inv.config inv.options) in
      let patterns, excludes = ok_or_die (validate opts) in
      match inv.command with
      | Write_config ->
          if not (Config.write_default Config.file_name) then
            die (Printf.sprintf "cannot overwrite existing '%s' file" Config.file_name)
      | List_patterns -> List.iter (fun g -> print_endline (Glob.source g)) patterns
      | Clean | Show_help | Show_version -> clean inv opts patterns excludes)

let () =
  try main () with
  | Sys_error msg -> die msg
  | Unix.Unix_error (e, _, arg) -> die (arg ^ ": " ^ Unix.error_message e)
