(** Removing matched paths through directory descriptors.

    Removal opens the root, following a symlink there, then each component
    below it with [O_NOFOLLOW]. A target whose kind, device or inode differs
    from the scan is refused, so a path swapped after the scan is not
    followed or removed. *)

type failure = {
  target : Target.t;
  path : string;  (** The path that failed: the target or an entry inside it. *)
  error : string;  (** The reason, without the path. *)
}

val remove :
  ?on_visit:(string -> unit) ->
  ?on_freed:(int -> unit) ->
  root:string ->
  Target.t ->
  (unit, string * string) result
(** Remove a target below [root], recursively if it is a directory, without
    following symlinks. A failure inside a directory does not stop removal of
    its siblings; the first failing path and its reason are returned. Each
    directory the user owns, the target included, gains owner rwx first; this
    needs owner read already. [on_visit] sees every path before its removal.
    [on_freed] gets the size of each non-directory removed. *)

val remove_all :
  ?on_remove:(Target.t -> unit) ->
  ?on_visit:(string -> unit) ->
  ?on_freed:(int -> unit) ->
  root:string ->
  Target.t list ->
  failure list
(** Remove every target, continuing past failures. [on_remove] runs before
    each attempt; [on_visit] and [on_freed] are passed to {!remove}. *)
