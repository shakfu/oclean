type failure = { target : Target.t; path : string; error : string }

let guard path f =
  match f () with v -> Ok v | exception Unix.Unix_error (e, _, _) -> Error (path, Unix.error_message e)

let ( let* ) = Result.bind

let with_fd fd f = Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

(* Remove [name] in the open directory [parent]; [st] is its lstat. *)
let rec remove_entry ~on_visit ~on_freed parent name path (st : At.stat) =
  on_visit path;
  if st.kind = S_DIR then
    let* fd = guard path (fun () -> At.openat_dir parent name) in
    let* () = with_fd fd (fun fd -> empty ~on_visit ~on_freed fd path) in
    guard path (fun () -> At.unlinkat parent name true)
  else
    let* () = guard path (fun () -> At.unlinkat parent name false) in
    on_freed st.size;
    Ok ()

(* Empty the open directory [fd], first granting owner rwx if the user owns
   it. Continues past failures and returns the first. *)
and empty ~on_visit ~on_freed fd path =
  let* now = guard path (fun () -> Unix.fstat fd) in
  let* () =
    if now.st_uid <> Unix.geteuid () || now.st_perm land 0o700 = 0o700 then Ok ()
    else guard path (fun () -> Unix.fchmod fd (now.st_perm lor 0o700))
  in
  let* names = guard path (fun () -> At.readdir fd) in
  List.fold_left
    (fun first name ->
      let child = path ^ "/" ^ name in
      let r =
        let* st = guard child (fun () -> At.lstatat fd name) in
        remove_entry ~on_visit ~on_freed fd name child st
      in
      if Result.is_error first then first else r)
    (Ok ()) names

let remove ?(on_visit = ignore) ?(on_freed = ignore) ~root (t : Target.t) =
  let prefix = if String.ends_with ~suffix:"/" root then root else root ^ "/" in
  let n = String.length prefix in
  if not (String.starts_with ~prefix t.path) || String.length t.path = n then Error (t.path, "not below the root")
  else
    let parents, name =
      match List.rev (String.split_on_char '/' (String.sub t.path n (String.length t.path - n))) with
      | name :: rev_parents -> (List.rev rev_parents, name)
      | [] -> assert false
    in
    let rec descend fd = function
      | dir :: rest ->
          let* sub = guard t.path (fun () -> At.openat_dir fd dir) in
          with_fd sub (fun sub -> descend sub rest)
      | [] ->
          let* st = guard t.path (fun () -> At.lstatat fd name) in
          if st.kind <> t.kind || st.dev <> t.dev || st.ino <> t.ino then Error (t.path, "replaced since the scan")
          else remove_entry ~on_visit ~on_freed fd name t.path st
    in
    (* The root itself may be a symlink. *)
    let* fd = guard t.path (fun () -> Unix.openfile root [ O_RDONLY; O_CLOEXEC ] 0) in
    with_fd fd (fun fd -> descend fd parents)

let remove_all ?(on_remove = ignore) ?on_visit ?on_freed ~root targets =
  List.filter_map
    (fun (t : Target.t) ->
      on_remove t;
      match remove ?on_visit ?on_freed ~root t with
      | Ok () -> None
      | Error (path, error) -> Some { target = t; path; error })
    targets
