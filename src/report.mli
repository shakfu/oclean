(** Turning targets into text or JSON. *)

type stat = { pattern : string; count : int; size : int }

type t = { targets : Target.t list; total_size : int; stats : stat list }

val summarize :
  ?measure:bool -> ?on_visit:(string -> unit) -> ?on_warning:(string -> string -> unit) -> Target.t list -> t
(** Compute totals and per-reason statistics, in order of first appearance.
    With [measure] (the default) directory targets are walked for their size,
    reporting each entry to [on_visit] and unreadable ones to [on_warning]. *)

val render_text : ?color:bool -> stats:bool -> t -> string
(** One [Matched: PATH] line per target; [stats] appends the breakdown.
    [color] highlights directories and sizes. *)

val render_json : dry_run:bool -> ?failures:Delete.failure list -> ?freed:int -> t -> string
(** One JSON object with [matches], [summary], [stats] and [failures]. [freed]
    is the bytes actually removed. *)

val render_removed : ?color:bool -> count:int -> freed:int -> unit -> string
(** The line printed after removal, e.g. [Removed 3 item(s), 4.88 KiB.] *)

val format_size : int -> string
(** Bytes in binary units with two decimals, e.g. [1.95 KiB]. *)
