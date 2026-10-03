open Harness

let target path is_dir pattern size = { Target.path; is_dir; reason = Pattern pattern; size }

let sample =
  [
    target "/tmp/p/.DS_Store" false "**/.DS_Store" 0;
    target "/tmp/p/__pycache__" true "**/__pycache__" 5000;
    target "/tmp/p/other/__pycache__" true "**/__pycache__" 1000;
  ]

let summary =
  Report.
    {
      targets = sample;
      total_size = 6000;
      stats =
        [ { pattern = "**/.DS_Store"; count = 1; size = 0 }; { pattern = "**/__pycache__"; count = 2; size = 6000 } ];
    }

let has out sub = check_bool sub (contains ~sub out)

let tests =
  group "Report"
    [
      it "formats byte counts with decimal units" (fun () ->
          check_string "zero" "0 B" (Report.format_size 0);
          check_string "bytes" "100 B" (Report.format_size 100);
          check_string "exact KB" "1.00 KB" (Report.format_size 1000);
          check_string "fractional KB" "1.02 KB" (Report.format_size 1024);
          check_string "rounded KB" "4.88 KB" (Report.format_size 4876);
          check_string "MB" "1.05 MB" (Report.format_size 1048576);
          check_string "GB" "2.50 GB" (Report.format_size 2_500_000_000);
          check_string "TB" "1.10 TB" (Report.format_size 1099511627776));
      it "lists matches as text" (fun () ->
          check_string "listing"
            "Matched: /tmp/p/.DS_Store\n\
             Matched: /tmp/p/__pycache__\n\
             Matched: /tmp/p/other/__pycache__\n"
            (Report.render_text ~stats:false summary));
      it "appends statistics when asked" (fun () ->
          check_string "with stats"
            "Matched: /tmp/p/.DS_Store\n\
             Matched: /tmp/p/__pycache__\n\
             Matched: /tmp/p/other/__pycache__\n\
            \  **/.DS_Store: 1 item(s), 0 B\n\
            \  **/__pycache__: 2 item(s), 6.00 KB\n"
            (Report.render_text ~stats:true summary));
      it "colours directories, sizes and the removal line" (fun () ->
          let out = Report.render_text ~color:true ~stats:true summary in
          has out "\027[2mMatched:\027[0m /tmp/p/.DS_Store\n";
          has out "\027[2mMatched:\027[0m \027[1;34m/tmp/p/__pycache__\027[0m\n";
          has out "2 item(s), \027[1m6.00 KB\027[0m\n";
          check_string "removed" "\027[32mRemoved 1 item(s), 0 B.\027[0m\n"
            (Report.render_removed ~color:true ~count:1 ~freed:0 ()));
      it "decides when to colour" (fun () ->
          let on ?(mode = Style.Auto) ?no_color ?(term = "xterm") ?(tty = true) () =
            Style.enabled ~mode ~no_color ~term:(Some term) ~tty
          in
          check_bool "terminal" (on ());
          check_bool "empty NO_COLOR" (on ~no_color:"" ());
          check_bool "NO_COLOR" (not (on ~no_color:"1" ()));
          check_bool "dumb terminal" (not (on ~term:"dumb" ()));
          check_bool "not a terminal" (not (on ~tty:false ()));
          check_bool "never" (not (on ~mode:Never ()));
          check_bool "always overrides" (on ~mode:Always ~no_color:"1" ~term:"dumb" ~tty:false ()));
      it "renders an empty report" (fun () ->
          check_string "nothing" ""
            (Report.render_text ~stats:true { targets = []; total_size = 0; stats = [] }));
      it "renders JSON with matches, summary and stats" (fun () ->
          let out = Report.render_json ~dry_run:true summary in
          List.iter (has out)
            [
              "\"matches\":[{\"path\":\"/tmp/p/.DS_Store\"";
              "\"size\":5000";
              "\"total_count\":3";
              "\"total_size\":6000";
              "\"total_size_human\":\"6.00 KB\"";
              "\"dry_run\":true";
              "\"count\":2";
              "\"failures\":[]";
            ]);
      it "reports the bytes freed" (fun () ->
          let out = Report.render_json ~dry_run:false ~freed:5000 summary in
          has out "\"freed_size\":5000";
          has out "\"freed_size_human\":\"5.00 KB\"";
          has (Report.render_json ~dry_run:true summary) "\"freed_size\":0";
          check_string "text line" "Removed 3 item(s), 5.00 KB.\n" (Report.render_removed ~count:3 ~freed:5000 ()));
      it "reports dry_run as false when deleting" (fun () ->
          has (Report.render_json ~dry_run:false summary) "\"dry_run\":false");
      it "reports removal failures" (fun () ->
          let failures = [ { Delete.target = List.hd sample; error = "/tmp/p/.DS_Store: Permission denied" } ] in
          has (Report.render_json ~dry_run:false ~failures summary)
            "\"failures\":[{\"path\":\"/tmp/p/.DS_Store\",\"error\":\"/tmp/p/.DS_Store: Permission denied\"}]");
      it "escapes JSON strings" (fun () ->
          let s = { Report.targets = [ target "a\"b\\c\nd\te" false "\001" 0 ]; total_size = 0; stats = [] } in
          let out = Report.render_json ~dry_run:false s in
          has out "a\\\"b";
          has out "b\\\\c";
          has out "c\\nd";
          has out "d\\te";
          has out "\\u0001";
          check_bool "no raw control character" (not (contains ~sub:"\001" out)));
      it "measures directories when summarising" (fun () ->
          with_tree [ ("cache/a.pyc", "0123456789"); ("cache/deep/b.pyc", "01234"); ("loose.txt", "xy") ]
            (fun root ->
              let s =
                Report.summarize [ target (root / "cache") true "**/cache" 0; target (root / "loose.txt") false "*.txt" 2 ]
              in
              let show xs = String.concat "," (List.map string_of_int xs) in
              check ~show "directory size" [ 15; 2 ] (List.map (fun (t : Target.t) -> t.size) s.targets);
              check_int "total" 17 s.total_size;
              check "stats"
                Report.[ { pattern = "**/cache"; count = 1; size = 15 }; { pattern = "*.txt"; count = 1; size = 2 } ]
                s.stats));
      it "skips measuring when asked" (fun () ->
          with_tree [ ("cache/a.pyc", "0123456789") ] (fun root ->
              let s = Report.summarize ~measure:false [ target (root / "cache") true "**/cache" 0 ] in
              check_int "unmeasured" 0 s.total_size));
    ]
