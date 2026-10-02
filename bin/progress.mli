(** The activity indicator on stderr: a spinner, an optional bar, a running
    count, the elapsed time and the path being visited.

    It paints only when stderr is a terminal, and only after the work has run
    for a quarter of a second. Repainting happens inside {!tick} and {!show},
    at most every 100 ms, so no thread is needed; the cost is that the spinner
    stops while a single system call blocks. *)

type mode =
  | Auto  (** Show it on a terminal once the work looks slow. *)
  | Always  (** Off a terminal, print one summary line at the end. *)
  | Never

type t

val with_progress :
  mode -> message:(int -> string) -> summary:(int -> string option) -> (t -> 'a) -> 'a
(** [message] renders the count into the live line. [summary] renders the final
    count into the line printed under [Always] off a terminal; [None] prints
    nothing. The indicator is erased when the function returns or raises. *)

val tick : t -> string -> unit
(** Count one item and show its path. *)

val show : t -> string -> unit
(** Show a path without counting it. *)

val set_message : t -> (int -> string) -> unit

val set_bar : t -> int -> int -> unit
(** [set_bar t done total] shows a bar at [done] of [total] steps. A [total]
    of 0 hides it. *)

val note : t -> string -> unit
(** Print a line on stderr without the indicator overwriting it. *)

val indicator_line : ?bar:int * int -> int -> char -> string -> string -> string
(** [indicator_line ~bar:(done, total) width frame message path], clipped to
    [width] bytes. The path is dropped when fewer than 12 columns are left for
    it. *)

val bar_text : int -> int -> string
(** [bar_text done total], e.g. [[#####...............] 1/4]. [total] must be
    positive. *)

val elapsed : float -> string
(** Seconds as [42s] or [3m05s]. *)

val shorten : int -> string -> string
(** Clip a path to [width] bytes, keeping the end. *)

val spinner_frame : int -> char
