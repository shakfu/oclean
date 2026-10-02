(** Glob patterns, compiled once and matched against paths relative to the scan
    root.

    A pattern with no slash matches the basename anywhere in the tree. [**] as
    a whole segment spans any number of directories. Within a segment [*]
    matches any run of characters, [?] matches one, and [[abc]], [[a-z]],
    [[!abc]] and [[^abc]] match a character class; a [\]] in first position is
    literal. [\\] is read as [/]. [?] and classes consume one UTF-8 character;
    an invalid byte counts as one character.

    Matching is O(pattern * path): a failed attempt restarts only from the most
    recent [*] or [**]. *)

type t

val compile : string -> (t, string) result
(** Fails with [invalid glob pattern: PAT] on an unterminated class. *)

val source : t -> string
(** The pattern as written. *)

val matches : t -> string -> bool
(** [matches g path] tests a [/]-separated relative path. *)

type path
(** A relative path split into segments, for testing against many globs. *)

val path : string -> path

val matches_path : t -> path -> bool
