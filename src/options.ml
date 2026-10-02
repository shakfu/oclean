(** Everything that selects and reports matches. Front ends fill it from
    arguments and a config file. *)

type format = Text | Json

type t = {
  root : string option;  (** Directory to scan; [None] means [.]. *)
  includes : string list;  (** Explicit include globs. *)
  excludes : string list;  (** Globs that prune the walk. *)
  presets : string list;  (** Named preset pattern sets. *)
  dry_run : bool;  (** Report matches without deleting. *)
  assume_yes : bool;  (** Skip the confirmation prompt. *)
  stats : bool;  (** Include per-pattern statistics. *)
  older_than : int option;  (** Only match entries at least this many seconds old. *)
  format : format;
  no_protect : bool;  (** Disable the protected-directory list. *)
  symlinks : bool;  (** Remove matching symlinks. *)
  broken_symlinks : bool;  (** Remove dangling symlinks. *)
  artifacts : bool;  (** Match build output directories. *)
  quiet : bool;  (** Suppress the text listing. *)
}

let default =
  {
    root = None;
    includes = [];
    excludes = [];
    presets = [];
    dry_run = false;
    assume_yes = false;
    stats = false;
    older_than = None;
    format = Text;
    no_protect = false;
    symlinks = false;
    broken_symlinks = false;
    artifacts = false;
    quiet = false;
  }

let root o = Option.value o.root ~default:"."
