(** A path selected for removal, and why it was selected. *)

type reason = Pattern of string | Build_artifact | Broken_symlink

type t = {
  path : string;
  is_dir : bool;
  reason : reason;
  size : int;  (** Bytes; 0 for a directory until measured. *)
}

let label = function
  | Pattern p -> p
  | Build_artifact -> "build-artifact"
  | Broken_symlink -> "broken-symlink"
