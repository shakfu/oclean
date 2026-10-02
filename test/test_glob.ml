open Harness

let matches pattern path =
  match Glob.compile pattern with Ok g -> Glob.matches g path | Error e -> fail "%s" e

let valid pattern = Result.is_ok (Glob.compile pattern)

let tests =
  group "Glob"
    [
      it "matches a slashless pattern against the basename" (fun () ->
          check_bool "*.pyc" (matches "*.pyc" "a/b/c.pyc");
          check_bool ".DS_Store" (matches ".DS_Store" "deep/nested/.DS_Store"));
      it "anchors patterns containing a slash to the whole path" (fun () ->
          check_bool "src/*.ml" (matches "src/*.ml" "src/main.ml");
          check_bool "not nested" (not (matches "src/*.ml" "src/a/main.ml"));
          check_bool "not elsewhere" (not (matches "src/*.ml" "lib/src/main.ml")));
      it "lets ** span any number of segments" (fun () ->
          check_bool "top level" (matches "**/__pycache__" "__pycache__");
          check_bool "one level" (matches "**/__pycache__" "a/__pycache__");
          check_bool "many levels" (matches "**/__pycache__" "a/b/c/__pycache__");
          check_bool "suffix must match" (not (matches "**/__pycache__" "a/__pycache__/b"));
          check_bool "middle" (matches "a/**/z" "a/b/c/z");
          check_bool "middle, zero segments" (matches "a/**/z" "a/z"));
      it "matches ? against exactly one character" (fun () ->
          check_bool "one" (matches "a?c.txt" "a-c.txt");
          check_bool "not zero" (not (matches "a?c.txt" "ac.txt"));
          check_bool "not two" (not (matches "a?c.txt" "a--c.txt")));
      it "treats ? and classes as one UTF-8 character" (fun () ->
          check_bool "two-byte character" (matches "caf?" "caf\xc3\xa9");
          check_bool "not one byte" (not (matches "caf??" "caf\xc3\xa9"));
          check_bool "star then ?" (matches "*?" "\xc3\xa9");
          check_bool "class range" (matches "[\xc3\xa0-\xc3\xbf].txt" "\xc3\xa9.txt"));
      it "treats backslashes as separators" (fun () ->
          check_bool "windows style" (matches "**\\target" "a/target");
          check_bool "anchored" (not (matches "src\\*.ml" "lib/src/main.ml")));
      it "matches character classes" (fun () ->
          check_bool "member" (matches "[abc].txt" "b.txt");
          check_bool "non-member" (not (matches "[abc].txt" "d.txt"));
          check_bool "range" (matches "file[0-9].log" "file7.log");
          check_bool "outside range" (not (matches "file[0-9].log" "filex.log"));
          check_bool "negated" (matches "[!abc].txt" "d.txt");
          check_bool "negated member" (not (matches "[!abc].txt" "a.txt"));
          check_bool "caret negation" (not (matches "[^abc].txt" "a.txt"));
          check_bool "literal ] first" (matches "[]a].txt" "].txt");
          check_bool "class needs one character" (not (matches "[abc]" "")));
      it "combines classes with other wildcards" (fun () ->
          check_bool "star and class" (matches "**/*.[ch]" "src/main.c");
          check_bool "wrong extension" (not (matches "**/*.[ch]" "src/main.rs")));
      it "accepts balanced patterns and rejects unterminated classes" (fun () ->
          check_bool "closed" (valid "[abc].txt");
          check_bool "bracket class" (valid "[]]");
          check_bool "no class" (valid "**/*.log");
          check_bool "unterminated" (not (valid "[abc.txt"));
          check_bool "empty class" (not (valid "x[]y"));
          check_bool "negated empty class" (not (valid "[!]"));
          match Glob.compile "[abc" with
          | Error e -> check_string "message" "invalid glob pattern: [abc" e
          | Ok _ -> fail "compiled an unterminated class");
      it "keeps the pattern as written" (fun () ->
          check_strings "sources" [ "**\\x"; "*.pyc" ] (List.map Glob.source (globs [ "**\\x"; "*.pyc" ])));
      it "matches pathological patterns in polynomial time" (fun () ->
          let pattern = String.concat "" (List.init 14 (fun _ -> "*a")) ^ "*b" in
          let path = String.make 200 'a' ^ "c" in
          let start = Unix.gettimeofday () in
          check_bool "no match" (not (matches pattern path));
          check_bool "fast" (Unix.gettimeofday () -. start < 1.0));
    ]

