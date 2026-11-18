type stat = { pattern : string; count : int; size : int }

type t = { targets : Target.t list; total_size : int; stats : stat list }

let sum_sizes = List.fold_left (fun n (t : Target.t) -> n + t.size) 0

let summarize ?(measure = true) ?on_visit ?on_warning targets =
  let targets =
    if not measure then targets
    else
      List.map
        (fun (t : Target.t) ->
          if Target.is_dir t then { t with size = Scan.directory_size ?on_visit ?on_warning t.path } else t)
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
  let rec scale x = function
    | _ :: (_ :: _ as larger) when x >= 1024. -> scale (x /. 1024.) larger
    | unit :: _ -> Printf.sprintf "%.2f %s" x unit
    | [] -> assert false
  in
  if n < 1024 then Printf.sprintf "%d B" n else scale (float_of_int n /. 1024.) [ "KiB"; "MiB"; "GiB"; "TiB" ]

let render_text ?(color = false) ~stats s =
  let b = Buffer.create 1024 in
  List.iter
    (fun (t : Target.t) ->
      let path = Util.escape t.path in
      let path = if Target.is_dir t then Style.blue ~color path else path in
      Printf.bprintf b "%s %s\n" (Style.dim ~color "Matched:") path)
    s.targets;
  if stats then
    List.iter
      (fun st ->
        Printf.bprintf b "  %s: %d item(s), %s\n" st.pattern st.count
          (Style.bold ~color (format_size st.size)))
      s.stats;
  Buffer.contents b

type json =
  | Bool of bool
  | Int of int
  | String of string
  | List of json list
  | Object of (string * json) list

(* Control characters are escaped. Each byte of an invalid UTF-8 sequence
   becomes U+FFFD, so the document is valid UTF-8. *)
let escape b s =
  let rec go i =
    if i < String.length s then
      match s.[i] with
      | '"' -> Buffer.add_string b "\\\""; go (i + 1)
      | '\\' -> Buffer.add_string b "\\\\"; go (i + 1)
      | '\n' -> Buffer.add_string b "\\n"; go (i + 1)
      | '\r' -> Buffer.add_string b "\\r"; go (i + 1)
      | '\t' -> Buffer.add_string b "\\t"; go (i + 1)
      | '\b' -> Buffer.add_string b "\\b"; go (i + 1)
      | '\012' -> Buffer.add_string b "\\f"; go (i + 1)
      | c when c < ' ' || c = '\127' -> Printf.bprintf b "\\u%04x" (Char.code c); go (i + 1)
      | c when c < '\128' -> Buffer.add_char b c; go (i + 1)
      | _ ->
          let d = String.get_utf_8_uchar s i in
          if Uchar.utf_decode_is_valid d then (
            let n = Uchar.utf_decode_length d in
            Buffer.add_string b (String.sub s i n);
            go (i + n))
          else (
            Buffer.add_utf_8_uchar b Uchar.rep;
            go (i + 1))
  in
  go 0

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
    Object [ ("path", String f.target.path); ("error", String (f.path ^ ": " ^ f.error)) ]
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

let render_removed ?(color = false) ~count ~freed () =
  Style.green ~color (Printf.sprintf "Removed %d item(s), %s." count (format_size freed)) ^ "\n"
