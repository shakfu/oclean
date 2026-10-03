(** Reading and writing [.oclean.toml].

    Only top-level [key = value] lines are read, with string, boolean and
    string-array values; [#] comments are ignored and reading stops at the
    first table header. Unknown keys are ignored. A known key with a value of
    the wrong type is an error.

    Precedence: a list given on the command line replaces the file's list, a
    flag set on the command line cannot be turned off by the file, and [path]
    from the file applies only when [--path] was not given. *)

type source =
  | No_config  (** Ignore configuration files. *)
  | Discover  (** Search upwards from the working directory, then the global file. *)
  | File of string  (** Read this file. *)

type value = String of string | Bool of bool | Array of string list

val file_name : string
(** [.oclean.toml]: looked for during discovery, written by [--write-configfile]. *)

val default_contents : string

val parse : string -> ((string * value) list, string) result
(** Parse file contents into key/value pairs, in file order. *)

val apply : string -> Options.t -> (Options.t, string) result
(** Merge the named file into the options. *)

val discover : string -> string option
(** [file_name] in the directory or its nearest ancestor below the home
    directory, else [oclean/config.toml] under [$XDG_CONFIG_HOME] (when
    absolute) or [~/.config], if it exists. A file in [~] or above it is never
    found. *)

val resolve : source -> Options.t -> (Options.t, string) result

val write_default : string -> bool
(** Create a starter file. [false] if the path already exists. *)
