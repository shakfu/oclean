type atom =
  | Byte of char
  | Any_char
  | Star
  | Class of { negated : bool; ranges : (Uchar.t * Uchar.t) list }

type segment = Globstar | Literal of string | Segment of atom array

type t = { source : string; basename_only : bool; segments : segment array }

let source g = g.source

let decode s i =
  let d = String.get_utf_8_uchar s i in
  (Uchar.utf_decode_uchar d, Uchar.utf_decode_length d)

let char_length s i = snd (decode s i)

(* Parse a class body starting just after '['; return it and the index after ']'. *)
let parse_class s start =
  let n = String.length s in
  let negated = start < n && (s.[start] = '!' || s.[start] = '^') in
  let rec collect ranges i =
    if i >= n then None
    else if s.[i] = ']' && ranges <> [] then
      Some (Class { negated; ranges = List.rev ranges }, i + 1)
    else
      let lo, len = decode s i in
      let j = i + len in
      if j + 1 < n && s.[j] = '-' && s.[j + 1] <> ']' then
        let hi, len' = decode s (j + 1) in
        collect ((lo, hi) :: ranges) (j + 1 + len')
      else collect ((lo, lo) :: ranges) j
  in
  collect [] (if negated then start + 1 else start)

let parse_segment s =
  if s = "**" then Some Globstar
  else if not (String.exists (fun c -> c = '*' || c = '?' || c = '[') s) then Some (Literal s)
  else
    let n = String.length s in
    let rec go acc i =
      if i >= n then Some (Segment (Array.of_list (List.rev acc)))
      else
        match s.[i], acc with
        | '*', Star :: _ -> go acc (i + 1)
        | '*', _ -> go (Star :: acc) (i + 1)
        | '?', _ -> go (Any_char :: acc) (i + 1)
        | '[', _ -> (
            match parse_class s (i + 1) with
            | Some (cls, j) -> go (cls :: acc) j
            | None -> None)
        | c, _ -> go (Byte c :: acc) (i + 1)
    in
    go [] 0

let compile pattern =
  let normalised = String.map (function '\\' -> '/' | c -> c) pattern in
  let rec parse acc = function
    | [] -> Some (Array.of_list (List.rev acc))
    | part :: rest -> Option.bind (parse_segment part) (fun seg -> parse (seg :: acc) rest)
  in
  match parse [] (String.split_on_char '/' normalised |> List.filter (( <> ) "")) with
  (* [**/x] matches exactly the paths whose basename matches [x]. *)
  | Some [| Globstar; (Literal _ | Segment _) as last |] ->
      Ok { source = pattern; basename_only = true; segments = [| last |] }
  | Some segments ->
      Ok { source = pattern; basename_only = not (String.contains normalised '/'); segments }
  | None -> Error ("invalid glob pattern: " ^ pattern)

(* Wildcard matching with a single restart point. [step p i] consumes pattern
   item [p] at subject position [i]; [advance i] moves a restart one unit on. *)
let backtrack ~np ~ns ~is_star ~step ~advance =
  let rec go p i restart =
    if p < np && is_star p then go (p + 1) i (Some (p + 1, i))
    else if p = np && i = ns then true
    else
      match if p < np then step p i else None with
      | Some i' -> go (p + 1) i' restart
      | None -> (
          match restart with
          | Some (rp, ri) when ri < ns ->
              let ri = advance ri in
              go rp ri (Some (rp, ri))
          | _ -> false)
  in
  go 0 0 None

let in_class u ranges =
  List.exists (fun (lo, hi) -> Uchar.compare lo u <= 0 && Uchar.compare u hi <= 0) ranges

let match_atoms atoms s =
  let ns = String.length s in
  let step p i =
    if i >= ns then None
    else
      match atoms.(p) with
      | Byte c -> if s.[i] = c then Some (i + 1) else None
      | Any_char -> Some (i + char_length s i)
      | Class { negated; ranges } ->
          let u, len = decode s i in
          if in_class u ranges <> negated then Some (i + len) else None
      | Star -> None
  in
  backtrack ~np:(Array.length atoms) ~ns
    ~is_star:(fun p -> match atoms.(p) with Star -> true | _ -> false)
    ~step ~advance:(fun i -> i + char_length s i)

let match_segment segment s =
  match segment with
  | Globstar -> true
  | Literal l -> String.equal l s
  | Segment atoms -> match_atoms atoms s

let match_segments segments parts =
  let ns = Array.length parts in
  let step p i = if i < ns && match_segment segments.(p) parts.(i) then Some (i + 1) else None in
  backtrack ~np:(Array.length segments) ~ns
    ~is_star:(fun p -> match segments.(p) with Globstar -> true | _ -> false)
    ~step ~advance:succ

type path = string array

let path s = String.split_on_char '/' s |> List.filter (( <> ) "") |> Array.of_list

let matches_path g parts =
  let n = Array.length parts in
  if g.basename_only then n > 0 && Array.length g.segments = 1 && match_segment g.segments.(0) parts.(n - 1)
  else match_segments g.segments parts

let matches g s = matches_path g (path s)
