type mode = Auto | Always | Never

type t = {
  live : bool;  (** Painting on a terminal. *)
  counting : bool;
  width : int;
  started : float;
  mutable count : int;
  mutable message : int -> string;
  mutable path : string;
  mutable bar : (int * int) option;  (** Steps done and total. *)
  mutable frame : int;
  mutable painted : bool;
  mutable last_paint : float;
}

let startup_delay = 0.25
let repaint_interval = 0.1

let spinner_frame n = "|/-\\".[n mod 4]

let is_continuation c = Char.code c land 0xC0 = 0x80

let shorten width path =
  let n = String.length path in
  if width <= 0 then ""
  else if n <= width then path
  else if width <= 3 then String.make width '.'
  else
    (* Start on a character boundary, so a UTF-8 sequence is not cut. *)
    let rec start i = if i < n && is_continuation path.[i] then start (i + 1) else i in
    let i = start (n - width + 3) in
    "..." ^ String.sub path i (n - i)

let bar_width = 20

let bar_text done_ total =
  let filled = bar_width * max 0 (min done_ total) / total in
  Printf.sprintf "[%s%s] %d/%d" (String.make filled '#') (String.make (bar_width - filled) '.') done_ total

let elapsed secs =
  let s = int_of_float secs in
  if s < 60 then Printf.sprintf "%ds" s else Printf.sprintf "%dm%02ds" (s / 60) (s mod 60)

let indicator_line ?bar width frame message path =
  let prefix =
    match bar with
    | Some (done_, total) when total > 0 -> Printf.sprintf "%c %s %s" frame (bar_text done_ total) message
    | _ -> Printf.sprintf "%c %s" frame message
  in
  let room = width - String.length prefix - 2 in
  if path = "" || room < 12 then String.sub prefix 0 (min width (String.length prefix))
  else prefix ^ "  " ^ shorten room path

let terminal_width () =
  match Option.bind (Sys.getenv_opt "COLUMNS") int_of_string_opt with
  | Some n when n >= 40 -> min n 120
  | _ -> 80

let erase t =
  if t.painted then (
    prerr_string ("\r" ^ String.make t.width ' ' ^ "\r");
    flush stderr;
    t.painted <- false)

let repaint t =
  if t.live then
    let now = Unix.gettimeofday () in
    if now -. t.started >= startup_delay && now -. t.last_paint >= repaint_interval then (
      prerr_string
        ("\r"
        ^ indicator_line ?bar:t.bar t.width (spinner_frame t.frame)
            (t.message t.count ^ ", " ^ elapsed (now -. t.started))
            t.path);
      flush stderr;
      t.frame <- t.frame + 1;
      t.painted <- true;
      t.last_paint <- now)

let show t path =
  if t.counting then (
    t.path <- path;
    repaint t)

let tick t path =
  if t.counting then (
    t.count <- t.count + 1;
    show t path)

let set_message t message = t.message <- message

let set_bar t done_ total =
  t.bar <- (if total > 0 then Some (done_, total) else None);
  repaint t

let note t msg =
  erase t;
  prerr_endline msg

let with_progress mode ~message ~summary f =
  let live = mode <> Never && Unix.isatty Unix.stderr in
  let t =
    {
      live;
      counting = live || mode = Always;
      width = terminal_width ();
      started = Unix.gettimeofday ();
      count = 0;
      message;
      path = "";
      bar = None;
      frame = 0;
      painted = false;
      last_paint = neg_infinity;
    }
  in
  let result = Fun.protect ~finally:(fun () -> erase t) (fun () -> f t) in
  if t.counting && not live then Option.iter prerr_endline (summary t.count);
  result
