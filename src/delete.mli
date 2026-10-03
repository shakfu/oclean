(** Removing matched paths. *)

type failure = { target : Target.t; error : string }

val remove :
  ?on_visit:(string -> unit) -> ?on_freed:(int -> unit) -> string -> (unit, string) result
(** Remove a path, recursively if it is a directory, without following
    symlinks. A failure inside a directory does not stop removal of its
    siblings; the first error is returned, prefixed with the path that
    failed. Each directory the user owns, [path] included, gains owner rwx
    first; this needs owner read already. [on_visit] sees every path before
    its removal. [on_freed] gets the size of each non-directory removed. *)

val remove_all :
  ?on_remove:(Target.t -> unit) ->
  ?on_visit:(string -> unit) ->
  ?on_freed:(int -> unit) ->
  Target.t list ->
  failure list
(** Remove every target, continuing past failures. [on_remove] runs before
    each attempt; [on_visit] and [on_freed] are passed to {!remove}. *)
