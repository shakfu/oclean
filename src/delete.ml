type failure = { target : Target.t; error : string }

let guard path f =
  match f () with
  | v -> Ok v
  | exception Unix.Unix_error (e, _, _) -> Error (path ^ ": " ^ Unix.error_message e)
  | exception Sys_error msg -> Error msg

let ( let* ) = Result.bind

(* Grants owner rwx through a descriptor, so a directory swapped for a symlink
   after [lstat] is refused rather than followed. *)
let make_writable path (st : Unix.stats) =
  let* fd = guard path (fun () -> Unix.openfile path [ O_RDONLY; O_CLOEXEC ] 0) in
  Fun.protect
    ~finally:(fun () -> Unix.close fd)
    (fun () ->
      let* now = guard path (fun () -> Unix.fstat fd) in
      if now.st_dev <> st.st_dev || now.st_ino <> st.st_ino then Error (path ^ ": replaced during removal")
      else guard path (fun () -> Unix.fchmod fd (st.st_perm lor 0o700)))

let rec remove ?(on_visit = ignore) ?(on_freed = ignore) path =
  on_visit path;
  let* st = guard path (fun () -> Unix.lstat path) in
  match st.st_kind with
  | S_DIR ->
      let* () =
        if st.st_uid <> Unix.geteuid () || st.st_perm land 0o700 = 0o700 then Ok () else make_writable path st
      in
      let* names = guard path (fun () -> Sys.readdir path) in
      let* () =
        Array.fold_left
          (fun first name ->
            let r = remove ~on_visit ~on_freed (Filename.concat path name) in
            if Result.is_error first then first else r)
          (Ok ()) names
      in
      guard path (fun () -> Unix.rmdir path)
  | _ ->
      let* () = guard path (fun () -> Unix.unlink path) in
      on_freed st.st_size;
      Ok ()

let remove_all ?(on_remove = ignore) ?on_visit ?on_freed targets =
  List.filter_map
    (fun (t : Target.t) ->
      on_remove t;
      match remove ?on_visit ?on_freed t.path with Ok () -> None | Error error -> Some { target = t; error })
    targets
