(** Named pattern sets, and the rules for turning options into patterns. *)

val names : string list
(** Every preset accepted on the command line or in a config file. *)

val lookup : string -> string list option
(** Patterns of a preset. Names are matched without regard to case. *)

val expand : string list -> string list
(** Concatenate presets without duplicates, ignoring unknown names. *)

val defaults : string list
(** Used when neither includes nor presets are given. *)

val protected : string list
(** Directories never entered or removed unless protection is disabled. *)

val resolve : Options.t -> string list
(** Includes plus expanded presets; {!defaults} when both are empty. *)
