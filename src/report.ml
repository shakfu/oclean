type stat = { pattern : string; count : int; size : int }

type t = { targets : Target.t list; total_size : int; stats : stat list }

let sum_sizes = List.fold_left (fun n (t : Target.t) -> n + t.size) 0

let summarize ?(measure = true) ?on_visit targets =
  let targets =
    if not measure then targets
    else
      List.map
        (fun (t : Target.t) ->
          if t.is_dir then { t with size = Scan.directory_size ?on_visit t.path } else t)
        targets
  in
  let label (t : Target.t) = Target.label t.reason in
  let stat pattern =
    let matching = List.filter (fun t -> label t = pattern) targets in
    { pattern; count = List.length matching; size = sum_sizes matching }
  in
  {
    targets;
    total_size = sum_sizes targets;
    stats = List.map stat (Util.dedup (List.map label targets));
  }

let format_size n =
  let units = [ ("TB", 1_000_000_000_000); ("GB", 1_000_000_000); ("MB", 1_000_000); ("KB", 1_000) ] in
  match List.find_opt (fun (_, scale) -> n >= scale) units with
  | Some (unit, scale) -> Printf.sprintf "%.2f %s" (float_of_int n /. float_of_int scale) unit
  | None -> Printf.sprintf "%d B" n

let render_text ~stats s =
  let b = Buffer.create 1024 in
  List.iter (fun (t : Target.t) -> Printf.bprintf b "Matched: %s\n" t.path) s.targets;
  if stats then
    List.iter
      (fun st ->
        Printf.bprintf b "  %s: %d item(s), %s\n" st.pattern st.count (format_size st.size))
      s.stats;
  Buffer.contents b

type json =
  | Bool of bool
  | Int of int
  | String of string
  | List of json list
  | Object of (string * json) list

(* Control characters are escaped; other bytes pass through, which is valid in
   a UTF-8 document. *)
let escape b s =
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | '\b' -> Buffer.add_string b "\\b"
      | '\012' -> Buffer.add_string b "\\f"
      | c when c < ' ' || c = '\127' -> Printf.bprintf b "\\u%04x" (Char.code c)
      | c -> Buffer.add_char b c)
    s

let rec write b = function
  | Bool x -> Buffer.add_string b (string_of_bool x)
  | Int n -> Buffer.add_string b (string_of_int n)
  | String s ->
      Buffer.add_char b '"';
      escape b s;
      Buffer.add_char b '"'
  | List xs -> sequence b '[' ']' (write b) xs
  | Object fields ->
      sequence b '{' '}'
        (fun (k, v) ->
          write b (String k);
          Buffer.add_char b ':';
          write b v)
        fields

and sequence : 'a. Buffer.t -> char -> char -> ('a -> unit) -> 'a list -> unit =
 fun b opening closing item xs ->
  Buffer.add_char b opening;
  List.iteri
    (fun i x ->
      if i > 0 then Buffer.add_char b ',';
      item x)
    xs;
  Buffer.add_char b closing

let render_json ~dry_run ?(failures = []) ?(freed = 0) s =
  let match_ (t : Target.t) =
    Object
      [ ("path", String t.path); ("size", Int t.size); ("pattern", String (Target.label t.reason)) ]
  in
  let stat st =
    Object
      [
        ("pattern", String st.pattern);
        ("count", Int st.count);
        ("size", Int st.size);
        ("size_human", String (format_size st.size));
      ]
  in
  let failure (f : Delete.failure) =
    Object [ ("path", String f.target.path); ("error", String f.error) ]
  in
  let doc =
    Object
      [
        ("matches", List (List.map match_ s.targets));
        ( "summary",
          Object
            [
              ("total_count", Int (List.length s.targets));
              ("total_size", Int s.total_size);
              ("total_size_human", String (format_size s.total_size));
              ("freed_size", Int freed);
              ("freed_size_human", String (format_size freed));
              ("dry_run", Bool dry_run);
            ] );
        ("stats", List (List.map stat s.stats));
        ("failures", List (List.map failure failures));
      ]
  in
  let b = Buffer.create 4096 in
  write b doc;
  Buffer.contents b

let render_removed ~count ~freed = Printf.sprintf "Removed %d item(s), %s.\n" count (format_size freed)
