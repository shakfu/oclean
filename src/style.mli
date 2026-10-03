(** ANSI colour for terminal output. *)

type mode = Auto | Always | Never

val parse_mode : string -> (mode, string) result
(** [auto], [always] or [never]. *)

val enabled : mode:mode -> no_color:string option -> term:string option -> tty:bool -> bool
(** Whether to colour a stream. [Auto] requires [NO_COLOR] unset or empty,
    [TERM] other than [dumb], and a terminal. *)

val dim : color:bool -> string -> string
val bold : color:bool -> string -> string
val blue : color:bool -> string -> string
(** Bold blue. *)

val green : color:bool -> string -> string
val yellow : color:bool -> string -> string
(** Bold yellow. *)

val red : color:bool -> string -> string
(** Bold red. *)
