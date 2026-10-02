(** Turning targets into text or JSON. *)

type stat = { pattern : string; count : int; size : int }

type t = { targets : Target.t list; total_size : int; stats : stat list }

val summarize : ?measure:bool -> ?on_visit:(string -> unit) -> Target.t list -> t
(** Compute totals and per-reason statistics, in order of first appearance.
    With [measure] (the default) directory targets are walked for their size,
    reporting each entry to [on_visit]. *)

val render_text : stats:bool -> t -> string
(** One [Matched: PATH] line per target; [stats] appends the breakdown. *)

val render_json : dry_run:bool -> ?failures:Delete.failure list -> ?freed:int -> t -> string
(** One JSON object with [matches], [summary], [stats] and [failures]. [freed]
    is the bytes actually removed. *)

val render_removed : count:int -> freed:int -> string
(** The line printed after removal, e.g. [Removed 3 item(s), 5.00 KB.] *)

val format_size : int -> string
(** Bytes in decimal units, as Finder shows them, e.g. [4.88 MB]. *)
