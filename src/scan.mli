(** Walking the file system and deciding what matches.

    A matching directory is reported whole and not descended into. Excluded and
    protected entries prune the walk. Symlinked directories are never followed,
    so link loops cannot make the walk diverge. *)

val scan :
  ?on_visit:(string -> unit) ->
  ?on_match:(Target.t -> unit) ->
  Options.t ->
  patterns:Glob.t list ->
  excludes:Glob.t list ->
  string ->
  Target.t list
(** [scan opts ~patterns ~excludes root] collects every selected entry under
    [root], in walk order. Patterns are matched against paths relative to
    [root]; the reason recorded is the first pattern that matched. The
    [includes], [excludes] and [presets] fields of [opts] are not read.
    [on_visit] sees every entry examined, [on_match] every match. *)

val is_build_artifact : string -> string -> bool
(** [is_build_artifact dir name]: is [dir/name] build output? Requires a
    project marker for [name] in [dir], and a [.git] in [dir] or an ancestor. *)

val directory_size : ?on_visit:(string -> unit) -> string -> int
(** Total bytes under a directory, not following symlinks. Unreadable entries
    count as 0. *)
