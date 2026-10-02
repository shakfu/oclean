(* Argument parsing and help text. The only module that knows about argv. *)

type command = Clean | List_patterns | Write_config | Show_help | Show_version

type t = {
  command : command;
  options : Options.t;
  config : Config.source;
  verbose : bool;  (** Log what is scanned and removed, on stderr. *)
  progress : Progress.mode;
}

let default =
  {
    command = Clean;
    options = Options.default;
    config = No_config;
    verbose = false;
    progress = Auto;
  }

let version = "oclean 0.1.0"

let parse args =
  let rec go t args =
    let set f rest = go { t with options = f t.options } rest in
    let format v rest =
      match v with
      | "json" -> set (fun o -> { o with Options.format = Json }) rest
      | "text" -> set (fun o -> { o with Options.format = Text }) rest
      | _ -> Error ("unknown output format: " ^ v)
    in
    match args with
    | [] -> Ok t
    | ("-h" | "--help") :: rest -> go { t with command = Show_help } rest
    | "--version" :: rest -> go { t with command = Show_version } rest
    | ("-l" | "--list") :: rest -> go { t with command = List_patterns } rest
    | ("-w" | "--write-configfile") :: rest -> go { t with command = Write_config } rest
    | ("-p" | "--path") :: v :: rest -> set (fun o -> { o with root = Some v }) rest
    | ("-g" | "--glob") :: v :: rest -> set (fun o -> { o with includes = o.includes @ [ v ] }) rest
    | ("-e" | "--exclude") :: v :: rest -> set (fun o -> { o with excludes = o.excludes @ [ v ] }) rest
    | "--preset" :: v :: rest -> set (fun o -> { o with presets = o.presets @ [ v ] }) rest
    | ("-d" | "--dry-run") :: rest -> set (fun o -> { o with dry_run = true }) rest
    | ("-y" | "--skip-confirmation") :: rest -> set (fun o -> { o with assume_yes = true }) rest
    | ("-s" | "--stats") :: rest -> set (fun o -> { o with stats = true }) rest
    | ("-i" | "--include-symlinks") :: rest -> set (fun o -> { o with symlinks = true }) rest
    | ("-r" | "--remove-broken-symlinks") :: rest ->
        set (fun o -> { o with broken_symlinks = true }) rest
    | ("-B" | "--build-artifacts") :: rest -> set (fun o -> { o with artifacts = true }) rest
    | "--no-protect" :: rest -> set (fun o -> { o with no_protect = true }) rest
    | ("-q" | "--quiet") :: rest -> set (fun o -> { o with quiet = true }) rest
    | ("-v" | "--verbose") :: rest -> go { t with verbose = true } rest
    | ("-P" | "--progress") :: rest -> go { t with progress = Always } rest
    | "--no-progress" :: rest -> go { t with progress = Never } rest
    | ("-o" | "--older-than") :: v :: rest ->
        Result.bind (Util.parse_duration v) (fun secs ->
            set (fun o -> { o with older_than = Some secs }) rest)
    | "--format" :: v :: rest -> format v rest
    (* -c takes an optional path; a following flag means "discover". *)
    | ("-c" | "--configfile") :: v :: rest when not (String.starts_with ~prefix:"-" v) ->
        go { t with config = File v } rest
    | ("-c" | "--configfile") :: rest -> go { t with config = Discover } rest
    | arg :: rest when String.starts_with ~prefix:"--format=" arg ->
        format (String.sub arg 9 (String.length arg - 9)) rest
    | arg :: _ -> Error ("unknown or incomplete option: " ^ arg)
  in
  go default args

let help =
  String.concat "\n"
    [
      "Safely remove files and directories matching glob patterns.";
      "";
      "Usage: oclean [OPTIONS]";
      "  -p, --path PATH               Working directory (default .)";
      "  -g, --glob GLOB               Include pattern (repeatable)";
      "  -e, --exclude GLOB            Exclude pattern (repeatable)";
      "      --preset NAME             " ^ String.concat ", " Preset.names;
      "  -d, --dry-run                 Preview matches";
      "  -y, --skip-confirmation       Do not prompt";
      "  -s, --stats                   Show statistics";
      "  -o, --older-than DURATION     s, m, h, d, or w";
      "  -B, --build-artifacts         Match project build output";
      "  -i, --include-symlinks        Remove matching symlinks";
      "  -r, --remove-broken-symlinks  Remove broken symlinks";
      "  -c, --configfile [PATH]       Read configuration (discovered if omitted)";
      "      --format text|json        Output format";
      "      --no-protect              Disable protected directories";
      "  -q, --quiet                   Suppress the match listing";
      "  -v, --verbose                 Log scanning and removal on stderr";
      "  -P, --progress                Always report progress, terminal or not";
      "      --no-progress             Never show the activity indicator";
      "  -l, --list                    List patterns";
      "  -w, --write-configfile        Write " ^ Config.file_name;
      "  -h, --help                    Show this help";
      "      --version                 Show version";
      "";
    ]
