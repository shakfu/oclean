open Harness

let duration = check ~show:(result string_of_int)
let malformed = Error "duration must be a number followed by a unit"

let tests =
  group "Util"
    [
      it "parses each duration unit" (fun () ->
          duration "seconds" (Ok 45) (Util.parse_duration "45s");
          duration "minutes" (Ok 1800) (Util.parse_duration "30m");
          duration "hours" (Ok 43200) (Util.parse_duration "12h");
          duration "days" (Ok 259200) (Util.parse_duration "3d");
          duration "weeks" (Ok 1209600) (Util.parse_duration "2w"));
      it "keeps multi-digit numbers in order" (fun () ->
          duration "12m is twelve minutes" (Ok 720) (Util.parse_duration "12m");
          duration "101s" (Ok 101) (Util.parse_duration "101s"));
      it "ignores surrounding whitespace" (fun () ->
          duration "padded" (Ok 60) (Util.parse_duration "  1m "));
      it "rejects malformed durations" (fun () ->
          duration "no unit" malformed (Util.parse_duration "30");
          duration "no digits" malformed (Util.parse_duration "m");
          duration "empty" malformed (Util.parse_duration "");
          duration "bad unit" (Error "duration unit must be s, m, h, d, or w")
            (Util.parse_duration "30y");
          duration "overflow" (Error "duration is too large")
            (Util.parse_duration "99999999999999999999s"));
      it "makes paths absolute and drops empty and dot segments" (fun () ->
          check_string "absolute" "/a/b" (Util.absolute "/a/./b/");
          check_string "relative" (Sys.getcwd () / "x") (Util.absolute "./x");
          check_string "root" "/" (Util.absolute "/"));
      it "removes duplicates keeping first occurrences" (fun () ->
          check_strings "dedup" [ "b"; "a"; "c" ] (Util.dedup [ "b"; "a"; "b"; "c"; "a" ]));
    ]
