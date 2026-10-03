oclean

Dependency-free OCaml command-line utility for recursively cleaning development detritus.

A port of [hclean](https://github.com/shakfu/hclean) 0.1.0, itself a port of rclean 0.4 (now [reclean](https://github.com/shakfu/reclean)). It keeps the safe defaults: protected directories, dry runs, confirmation before deletion, symlink guards, age filtering, build-artifact detection, configuration discovery, statistics and JSON output. It uses only the OCaml standard library and `unix`, both of which ship with the compiler (tested with 4.14.1).

## Building

```sh
make          # builds ./oclean
make test     # builds and runs the test suite
make install  # installs to ~/.local/bin; override with PREFIX=/usr/local
```

The Makefile calls `ocamlopt` directly; dune, opam and ocamlfind are not needed.

## Usage

```sh
oclean --dry-run
oclean --glob '**/*.log' --skip-confirmation
oclean --preset node --dry-run
```

Run `oclean --help` for the full option list.

Matches are printed on stdout. The confirmation prompt (`Delete N item(s)? [y/N]`) goes to stderr, so stdout carries only the report. With `--format json` the report is printed after removal, and its `failures` array lists every target that could not be removed. A failed removal does not stop the run; oclean removes what it can, then exits 1.

After removal, a `Removed N item(s), SIZE.` line reports the bytes actually freed; `-q` suppresses it. In JSON these are `freed_size` and `freed_size_human` in `summary`. Sizes are apparent sizes (`st_size`), as with `--stats`, not disk blocks. Units are decimal (1 MB = 1,000,000 bytes), as in Finder.

While scanning or removing, oclean shows an activity indicator on stderr: a spinner, counts, elapsed time and the current path. Removal adds a progress bar. It appears only when stderr is a terminal and the work has run for 0.25 s, and is erased before results are printed. `--progress` forces reporting off a terminal, as one `scanned N entries` line at the end; `--no-progress` disables it.

On a terminal, directory matches are bold blue, sizes bold, the removal line green, the prompt yellow and the `oclean:` error prefix red. `--color` takes `auto`, `always` or `never`. Under `auto`, the default, a stream is coloured only when it is a terminal, `TERM` is not `dumb`, and `NO_COLOR` is unset or empty. `always` overrides all three, for `oclean -d --color=always | less -R`. JSON is never coloured.

- Scanning shows entries visited and matches found. It has no bar, since the total is unknown until the walk ends.

- Removal's bar counts targets, beside the bytes freed so far. With `--stats` or `--format json`, the total is shown as well.

## Patterns

Patterns are matched against paths relative to the scan root.

- A pattern with no slash matches a basename anywhere in the tree.

- `**` as a whole segment spans any number of directories.

- Within a segment, `*` matches any run of characters and `?` matches one.

- `[abc]`, `[a-z]`, `[!abc]` and `[^abc]` match a character class. A `]` in first position is literal.

- `\` is read as `/`, so there is no escape character.

`?` and classes consume one UTF-8 character. A directory that matches is removed whole and is not descended into. An unterminated class is rejected, in excludes as well as includes.

## Build artifacts

`-B` matches build output directories (`build`, `dist`, `target`, `.next`, `_build`, `zig-out` and others). A directory matches only when the project marker that produces it (`Cargo.toml`, `package.json`, `mix.exs`, ...) sits beside it, and a `.git` exists in that directory or an ancestor below the home directory. The ancestor rule covers workspace members such as `crates/foo/target`; the home boundary keeps a dotfiles repository in `~` from qualifying every project under it.

## Configuration

`oclean -c` reads `.oclean.toml` from the working directory or its nearest ancestor, falling back to the global `oclean/config.toml` under `$XDG_CONFIG_HOME`, or under `~/.config` when that is unset or relative. The search stops below the home directory, so a `.oclean.toml` in `~` or above it is never read; user-wide settings belong in the global file. `oclean -c FILE` reads that file. Without `-c`, no configuration is read. Only one file is read per run, and files are not merged.

```toml
path = "."
patterns = ["**/__pycache__", "**/*.pyc"]
exclude_patterns = ["**/vendor"]
presets = ["python", "node"]
dry_run = false
skip_confirmation = false
stats_mode = false
include_symlinks = false
remove_broken_symlinks = false
build_artifacts = false
```

The reader accepts top-level keys with string, boolean and string-array values, and `#` comments. Unknown keys are ignored. A known key with a value of the wrong type is an error.

Precedence:

- A list given on the command line (`--glob`, `--exclude`, `--preset`) replaces the file's list.

- A flag set on the command line cannot be switched off by the file.

- `--path` overrides the file's `path`.

## Layout

```
src/util.ml      durations, path and list helpers
src/glob.ml      glob compilation and matching
src/options.ml   Options.t, the run settings
src/target.ml    Target.t, a match and its reason
src/preset.ml    named pattern sets, protected directories
src/scan.ml      directory walk, build-artifact detection, sizes
src/delete.ml    removal, collecting failures
src/style.ml     ANSI colour and when to use it
src/report.ml    summaries, text and JSON rendering
src/config.ml    .oclean.toml reading, discovery and writing
bin/progress.ml  the stderr activity indicator
bin/cli.ml       argument parsing and help text
bin/main.ml      wiring, prompting and exit codes
test/            test suite and its harness
```

The modules under `src/` never read argv, prompt or exit. Each has an `.mli` with its documentation.

## Differences from hclean

oclean fixed these hclean 0.1.0 defects. Each fix has a regression test. hclean's unreleased branch has since backported them all.

- `-c` without a path searches ancestors of the working directory. hclean never left `.`.

- `-B` finds `.git` in any ancestor, so workspace members match.

- `-o` applies to broken symlinks (`-r`).

- `-l` honours `--glob`.

- `-q` no longer shows a prompt with nothing above it. The prompt states the item count.

- TOML keys are matched exactly, comments are stripped, and type errors are reported.

- `--path` overrides a config file's `path`.

- A failed removal no longer aborts the run, and JSON `failures` is populated.

- Glob matching is O(pattern * path) instead of exponential, and `x[]y` is rejected instead of silently matching nothing.

- Directory sizes are measured only for `--stats` and JSON output.

- Non-UTF-8 file names print without crashing.

Remaining differences from current hclean:

- Sizes use decimal units (KB). hclean uses binary units (KiB).

- A relative `path` in a config file resolves against the working directory. hclean resolves it against the file's directory.

- Bytes freed are summed as files are unlinked. hclean measures each target before removal and subtracts what a failure left.

## Known limitations

- JSON output copies file-name bytes as they are. A non-UTF-8 name produces invalid JSON.

- Terminal width comes from `COLUMNS`, and defaults to 80. The stdlib and `unix` do not expose `TIOCGWINSZ`.

- The config file has no keys for `--older-than`, `--format`, `--quiet` or `--no-protect`. This matches hclean.
