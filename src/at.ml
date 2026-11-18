(* Descriptor-relative calls, from at_stubs.c. Each raises Unix.Unix_error. *)

type stat = { kind : Unix.file_kind; dev : int; ino : int; size : int }

external openat_dir : Unix.file_descr -> string -> Unix.file_descr = "oclean_openat_dir"
(** Open a directory below [dir] with [O_NOFOLLOW], so a symlink fails. *)

external lstatat : Unix.file_descr -> string -> stat = "oclean_lstatat"
(** [fstatat] with [AT_SYMLINK_NOFOLLOW]. *)

external unlinkat : Unix.file_descr -> string -> bool -> unit = "oclean_unlinkat"
(** [unlinkat dir name is_dir]; [is_dir] passes [AT_REMOVEDIR]. *)

external readdir : Unix.file_descr -> string list = "oclean_readdir_fd"
(** Names in an open directory, without [.] and [..]. *)
