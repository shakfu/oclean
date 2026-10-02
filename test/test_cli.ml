open Harness

let parse args = Result.get_ok (Cli.parse args)
let options args = Result.map (fun (t : Cli.t) -> t.options) (Cli.parse args)
let error args = match Cli.parse args with Ok _ -> fail "parsed %s" (strs args) | Error e -> e

let tests =
  group "Cli"
    [
      it "defaults to cleaning the current directory" (fun () ->
          let t = parse [] in
          check_bool "command" (t.command = Clean);
          check_bool "options" (t.options = Options.default);
          check_bool "no path given" (t.options.root = None);
          check_bool "config" (t.config = No_config));
      it "accepts long and short spellings of each flag" (fun () ->
          List.iter
            (fun (short, long) -> check_bool short (options [ short ] = options [ long ]))
            [
              ("-d", "--dry-run");
              ("-y", "--skip-confirmation");
              ("-s", "--stats");
              ("-i", "--include-symlinks");
              ("-r", "--remove-broken-symlinks");
              ("-B", "--build-artifacts");
              ("-q", "--quiet");
            ]);
      it "sets the flags it is given" (fun () ->
          check_bool "dry run" (parse [ "-d" ]).options.dry_run;
          check_bool "assume yes" (parse [ "-y" ]).options.assume_yes;
          check_bool "artifacts" (parse [ "-B" ]).options.artifacts;
          check_bool "no protect" (parse [ "--no-protect" ]).options.no_protect;
          check_bool "path" ((parse [ "-p"; "x" ]).options.root = Some "x"));
      it "collects repeated globs, excludes and presets in order" (fun () ->
          check_strings "globs" [ "a"; "b" ] (parse [ "-g"; "a"; "--glob"; "b" ]).options.includes;
          check_strings "excludes" [ "x"; "y" ] (parse [ "-e"; "x"; "--exclude"; "y" ]).options.excludes;
          check_strings "presets" [ "node"; "rust" ]
            (parse [ "--preset"; "node"; "--preset"; "rust" ]).options.presets);
      it "parses the age limit" (fun () ->
          check_bool "hours" ((parse [ "-o"; "2h" ]).options.older_than = Some 7200);
          check_string "bad unit" "duration unit must be s, m, h, d, or w" (error [ "--older-than"; "2y" ]));
      it "parses the output format in both spellings" (fun () ->
          check_bool "space" ((parse [ "--format"; "json" ]).options.format = Json);
          check_bool "equals" ((parse [ "--format=json" ]).options.format = Json);
          check_bool "text" ((parse [ "--format"; "text" ]).options.format = Text);
          check_string "unknown" "unknown output format: yaml" (error [ "--format=yaml" ]));
      it "treats the config path as optional" (fun () ->
          check_bool "with path" ((parse [ "-c"; "cfg.toml" ]).config = File "cfg.toml");
          check_bool "bare" ((parse [ "-c" ]).config = Discover);
          check_bool "followed by a flag" ((parse [ "-c"; "-d" ]).config = Discover);
          check_bool "still parses the flag" (parse [ "-c"; "-d" ]).options.dry_run);
      it "enables the diagnostics flags" (fun () ->
          check_bool "verbose" (parse [ "-v" ]).verbose;
          check_bool "long verbose" (parse [ "--verbose" ]).verbose;
          check_bool "progress" ((parse [ "-P" ]).progress = Always);
          check_bool "long progress" ((parse [ "--progress" ]).progress = Always);
          check_bool "no progress" ((parse [ "--no-progress" ]).progress = Never);
          check_bool "automatic by default" ((parse []).progress = Auto);
          check_bool "off by default" (not (parse []).verbose));
      it "recognises the non-cleaning commands" (fun () ->
          check_bool "help" ((parse [ "--help" ]).command = Show_help);
          check_bool "short help" ((parse [ "-h" ]).command = Show_help);
          check_bool "version" ((parse [ "--version" ]).command = Show_version);
          check_bool "list" ((parse [ "-l" ]).command = List_patterns);
          check_bool "write config" ((parse [ "-w" ]).command = Write_config));
      it "reports unknown and incomplete options" (fun () ->
          check_string "unknown" "unknown or incomplete option: --bogus" (error [ "--bogus" ]);
          check_string "missing value" "unknown or incomplete option: -g" (error [ "-g" ]);
          check_string "missing path" "unknown or incomplete option: --path" (error [ "--path" ]));
      it "documents every option it accepts" (fun () ->
          let words =
            String.split_on_char '\n' Cli.help
            |> List.concat_map (String.split_on_char ' ')
            |> List.map (fun w -> List.hd (String.split_on_char ',' w))
          in
          List.iter
            (fun flag -> check_bool (flag ^ " is undocumented") (List.mem flag words))
            [ "-p"; "-g"; "-e"; "--preset"; "-d"; "-y"; "-s"; "-o"; "-B"; "-i"; "-r"; "-c"; "--format";
              "--no-protect"; "-q"; "-v"; "-P"; "--no-progress"; "-l"; "-w"; "-h"; "--version" ]);
    ]
