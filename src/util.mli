(** Small helpers shared by the other modules. *)

val parse_duration : string -> (int, string) result
(** [parse_duration "30m"] is [Ok 1800]. Units are [s], [m], [h], [d] and [w];
    surrounding whitespace is ignored. *)

val absolute : string -> string
(** Absolute form of a path, with empty and [.] segments removed. [..] is kept,
    since resolving it lexically is wrong across symlinks. *)

val is_file : string -> bool
(** Does the path exist and name something other than a directory? *)

val dedup : string list -> string list
(** Drop repeated elements, keeping the first occurrence of each. *)
