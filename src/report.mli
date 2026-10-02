(** Turning targets into text or JSON. *)

type stat = { pattern : string; count : int; size : int }

type t = { targets : Target.t list; total_size : int; stats : stat list }

val summarize : ?measure:bool -> ?on_visit:(string -> unit) -> Target.t list -> t
(** Compute totals and per-reason statistics, in order of first appearance.
    With [measure] (the default) directory targets are walked for their size,
    reporting each entry to [on_visit]. *)

val render_text : stats:bool -> t -> string
(** One [Matched: PATH] line per target; [stats] appends the breakdown. *)

val render_json : dry_run:bool -> ?failures:Delete.failure list -> t -> string
(** One JSON object with [matches], [summary], [stats] and [failures]. *)

val format_size : int -> string
(** Bytes in binary units, e.g. [4.88 KiB]. *)
