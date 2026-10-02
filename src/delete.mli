(** Removing matched paths. *)

type failure = { target : Target.t; error : string }

val remove : ?on_visit:(string -> unit) -> string -> (unit, string) result
(** Remove a path, recursively if it is a directory, without following
    symlinks. A failure inside a directory does not stop removal of its
    siblings; the first error is returned, prefixed with the path that
    failed. [on_visit] sees every path before its removal. *)

val remove_all :
  ?on_remove:(Target.t -> unit) -> ?on_visit:(string -> unit) -> Target.t list -> failure list
(** Remove every target, continuing past failures. [on_remove] runs before
    each attempt; [on_visit] is passed to {!remove}. *)
