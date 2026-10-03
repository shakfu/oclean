type mode = Auto | Always | Never

let parse_mode = function
  | "auto" -> Ok Auto
  | "always" -> Ok Always
  | "never" -> Ok Never
  | v -> Error ("unknown color mode: " ^ v)

(* An explicit mode overrides NO_COLOR, as https://no-color.org asks. *)
let enabled ~mode ~no_color ~term ~tty =
  match mode with
  | Always -> true
  | Never -> false
  | Auto -> (no_color = None || no_color = Some "") && term <> Some "dumb" && tty

let sgr code ~color s = if color then "\027[" ^ code ^ "m" ^ s ^ "\027[0m" else s
let dim = sgr "2"
let bold = sgr "1"
let blue = sgr "1;34"
let green = sgr "32"
let yellow = sgr "1;33"
let red = sgr "1;31"
