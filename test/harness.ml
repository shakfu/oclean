(* A small dependency-free test harness. *)

exception Failed of string

let fail fmt = Printf.ksprintf (fun m -> raise (Failed m)) fmt

let check ?(show = fun _ -> "<value>") label expected actual =
  if expected <> actual then fail "%s: expected %s, got %s" label (show expected) (show actual)

let str = Printf.sprintf "%S"
let strs xs = "[" ^ String.concat "; " (List.map str xs) ^ "]"
let result ok = function Ok x -> "Ok " ^ ok x | Error e -> "Error " ^ str e
let pair a b (x, y) = "(" ^ a x ^ ", " ^ b y ^ ")"

let check_string = check ~show:str
let check_strings = check ~show:strs
let check_int = check ~show:string_of_int
let check_bool label b = if not b then fail "%s" label

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec go i = i + n <= m && (String.sub s i n = sub || go (i + 1)) in
  go 0

let it name run = (name, run)
let group name tests = (name, tests)

let run groups =
  let total = ref 0 and failed = ref 0 in
  List.iter
    (fun (group, tests) ->
      List.iter
        (fun (name, f) ->
          incr total;
          let report msg =
            incr failed;
            Printf.printf "FAIL %s: %s\n  %s\n%!" group name msg
          in
          match f () with
          | () -> ()
          | exception Failed msg -> report msg
          | exception e -> report ("raised " ^ Printexc.to_string e))
        tests)
    groups;
  Printf.printf "%d tests, %d failed\n" !total !failed;
  exit (if !failed = 0 then 0 else 1)

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then (
    mkdir_p (Filename.dirname dir);
    Sys.mkdir dir 0o755)

let write_file path contents =
  Out_channel.with_open_bin path (fun oc -> output_string oc contents)

let read_file path = In_channel.with_open_bin path In_channel.input_all

let counter = ref 0

let rec fresh_dir () =
  incr counter;
  let dir =
    (* Resolved, so paths match what the binary derives from getcwd (macOS /var). *)
    Filename.concat (Unix.realpath (Filename.get_temp_dir_name ()))
      (Printf.sprintf "oclean-test-%d-%d" (Unix.getpid ()) !counter)
  in
  match Sys.mkdir dir 0o755 with () -> dir | exception Sys_error _ -> fresh_dir ()

(* Populate a fresh temporary directory and pass its path to [f]. Entries
   ending in '/' become directories, the rest files with the given contents. *)
let with_tree entries f =
  let root = fresh_dir () in
  List.iter
    (fun (path, contents) ->
      let full = Filename.concat root path in
      if String.ends_with ~suffix:"/" path then mkdir_p full
      else (
        mkdir_p (Filename.dirname full);
        write_file full contents))
    entries;
  Fun.protect ~finally:(fun () -> ignore (Delete.remove root)) (fun () -> f root)

let in_directory dir f =
  let saved = Sys.getcwd () in
  Sys.chdir dir;
  Fun.protect ~finally:(fun () -> Sys.chdir saved) f

let ( / ) = Filename.concat

let globs patterns =
  List.map (fun p -> match Glob.compile p with Ok g -> g | Error e -> fail "%s" e) patterns

(* Permission checks do not apply to root, so tests relying on them skip. *)
let as_root () = Unix.geteuid () = 0
