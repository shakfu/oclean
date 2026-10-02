type failure = { target : Target.t; error : string }

let guard path f =
  match f () with
  | v -> Ok v
  | exception Unix.Unix_error (e, _, _) -> Error (path ^ ": " ^ Unix.error_message e)
  | exception Sys_error msg -> Error msg

let ( let* ) = Result.bind

let rec remove ?(on_visit = ignore) ?(on_freed = ignore) path =
  on_visit path;
  let* st = guard path (fun () -> Unix.lstat path) in
  match st.st_kind with
  | S_DIR ->
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
