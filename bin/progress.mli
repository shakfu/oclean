(** The activity indicator on stderr: a spinner, a running count and the path
    being visited.

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

val note : t -> string -> unit
(** Print a line on stderr without the indicator overwriting it. *)

val indicator_line : int -> char -> string -> string -> string
(** [indicator_line width frame message path], clipped to [width] bytes. The
    path is dropped when fewer than 12 columns are left for it. *)

val shorten : int -> string -> string
(** Clip a path to [width] bytes, keeping the end. *)

val spinner_frame : int -> char
