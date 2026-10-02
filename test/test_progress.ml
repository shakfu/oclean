open Harness

(* Run [f] with stderr pointed at a file, which is not a terminal, and return
   what it wrote. *)
let capture_stderr f =
  with_tree [] (fun dir ->
      let path = dir / "stderr" in
      flush stderr;
      let saved = Unix.dup Unix.stderr in
      let fd = Unix.openfile path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 in
      Unix.dup2 fd Unix.stderr;
      Unix.close fd;
      let result =
        Fun.protect
          ~finally:(fun () ->
            flush stderr;
            Unix.dup2 saved Unix.stderr;
            Unix.close saved)
          f
      in
      (read_file path, result))

let ticks p n = for i = 1 to n do Progress.tick p (Printf.sprintf "/tmp/%d" i) done

let tests =
  group "Progress"
    [
      it "turns the spinner" (fun () ->
          check_string "frames" "|/-\\|" (String.init 5 Progress.spinner_frame));
      it "keeps the informative end of a path" (fun () ->
          check_string "short enough" "a/b/c" (Progress.shorten 10 "a/b/c");
          check_string "exact fit" "a/b/c" (Progress.shorten 5 "a/b/c");
          check_string "clipped" ".../d/e" (Progress.shorten 7 "/a/b/c/d/e");
          check_string "no room" "" (Progress.shorten 0 "/a/b");
          check_string "almost no room" ".." (Progress.shorten 2 "/a/b");
          check_string "whole characters" "...b" (Progress.shorten 5 "abc\xc3\xa9b"));
      it "lays out the indicator line" (fun () ->
          check_string "with path" "| scanning, 12 entries  /tmp/x"
            (Progress.indicator_line 80 '|' "scanning, 12 entries" "/tmp/x");
          check_string "path dropped when there is no room" "/ scanning, 12 entries"
            (Progress.indicator_line 25 '/' "scanning, 12 entries" "/tmp/some/deep/path");
          check_string "path clipped to the width" "| working  .../deep/path"
            (Progress.indicator_line 24 '|' "working" "/tmp/some/deep/path");
          check_string "message clipped to the width" "| scanni"
            (Progress.indicator_line 8 '|' "scanning, 12 entries" ""));
      it "draws a bar for a known total" (fun () ->
          check_string "empty" "[....................] 0/4" (Progress.bar_text 0 4);
          check_string "quarter" "[#####...............] 1/4" (Progress.bar_text 1 4);
          check_string "full" "[####################] 4/4" (Progress.bar_text 4 4);
          check_string "overrun is clamped" "[####################] 5/4" (Progress.bar_text 5 4);
          check_string "in the line" "| [##########..........] 2/4 removing  /tmp/x"
            (Progress.indicator_line ~bar:(2, 4) 80 '|' "removing" "/tmp/x");
          check_string "hidden without a total" "| removing"
            (Progress.indicator_line ~bar:(0, 0) 80 '|' "removing" ""));
      it "formats elapsed time" (fun () ->
          check_string "seconds" "42s" (Progress.elapsed 42.9);
          check_string "minutes" "3m05s" (Progress.elapsed 185.));
      it "stays silent when stderr is not a terminal" (fun () ->
          let written, () =
            capture_stderr (fun () ->
                Progress.with_progress Auto ~message:(fun _ -> "scanning") ~summary:(fun _ -> Some "done")
                  (fun p -> ticks p 10))
          in
          check_string "nothing painted" "" written);
      it "says nothing at all when disabled" (fun () ->
          let written, () =
            capture_stderr (fun () ->
                Progress.with_progress Never ~message:(fun _ -> "scanning") ~summary:(fun _ -> Some "done")
                  (fun p -> ticks p 1))
          in
          check_string "silent" "" written);
      it "summarises off a terminal when progress is forced" (fun () ->
          let written, () =
            capture_stderr (fun () ->
                Progress.with_progress Always ~message:(fun _ -> "scanning")
                  ~summary:(fun n -> Some (Printf.sprintf "scanned %d entries" n))
                  (fun p ->
                    ticks p 3;
                    Progress.show p "/tmp/uncounted"))
          in
          check_string "one summary line" "scanned 3 entries\n" written);
      it "omits the summary when there is none to give" (fun () ->
          let written, () =
            capture_stderr (fun () ->
                Progress.with_progress Always ~message:(fun _ -> "removing") ~summary:(fun _ -> None)
                  (fun p -> ticks p 1))
          in
          check_string "quiet" "" written);
      it "prints notes whatever the mode" (fun () ->
          let written, () =
            capture_stderr (fun () ->
                Progress.with_progress Never ~message:(fun _ -> "scanning") ~summary:(fun _ -> None)
                  (fun p ->
                    Progress.note p "root: /tmp";
                    Progress.note p "match: /tmp/x"))
          in
          check_string "both lines" "root: /tmp\nmatch: /tmp/x\n" written);
      it "returns the action's result" (fun () ->
          let _, value =
            capture_stderr (fun () ->
                Progress.with_progress Never ~message:(fun _ -> "scanning") ~summary:(fun _ -> None)
                  (fun _ -> 42))
          in
          check_int "passed through" 42 value);
    ]
