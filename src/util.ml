let parse_duration raw =
  let s = String.trim raw in
  let n = String.length s in
  let rec digits i = if i < n && s.[i] >= '0' && s.[i] <= '9' then digits (i + 1) else i in
  let d = digits 0 in
  if d = 0 || n <> d + 1 then Error "duration must be a number followed by a unit"
  else
    match int_of_string_opt (String.sub s 0 d), s.[d] with
    | None, _ -> Error "duration is too large"
    | Some k, 's' -> Ok k
    | Some k, 'm' -> Ok (k * 60)
    | Some k, 'h' -> Ok (k * 3600)
    | Some k, 'd' -> Ok (k * 86400)
    | Some k, 'w' -> Ok (k * 604800)
    | Some _, _ -> Error "duration unit must be s, m, h, d, or w"

let absolute path =
  let path = if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path in
  String.split_on_char '/' path
  |> List.filter (fun s -> s <> "" && s <> ".")
  |> String.concat "/"
  |> ( ^ ) "/"

let is_file path = Sys.file_exists path && not (Sys.is_directory path)

let dedup xs =
  List.rev (List.fold_left (fun seen x -> if List.mem x seen then seen else x :: seen) [] xs)
