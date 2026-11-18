(** A path selected for removal, and why it was selected. *)

type reason = Pattern of string | Build_artifact | Broken_symlink

type t = {
  path : string;
  kind : Unix.file_kind;
  dev : int;
  ino : int;  (** [kind], [dev] and [ino] are recorded by the scan; removal refuses a mismatch. *)
  reason : reason;
  size : int;  (** Bytes; 0 for a directory until measured. *)
}

let is_dir t = t.kind = Unix.S_DIR

let label = function
  | Pattern p -> p
  | Build_artifact -> "build-artifact"
  | Broken_symlink -> "broken-symlink"
