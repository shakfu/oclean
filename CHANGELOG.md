# Changelog

All notable changes to oclean are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First version: a port of hclean 0.1.0 to OCaml, using only the standard library and `unix`. Options, presets, the config file format and the output formats are unchanged. The config file is `.oclean.toml`, with `~/.config/oclean/config.toml` as the global fallback, so oclean and rclean settings do not interfere. See [README.md](README.md#differences-from-hclean) for the hclean defects fixed in the port.

- Globs are compiled once into a pattern tree. A segment with no metacharacters is compared as a string, and `**/x` is matched as the basename pattern `x`. The `--preset all` scan of a 237k-entry tree took 7.3 s before these fast paths and takes 1.4 s with them.

- The activity indicator repaints from the scan loop instead of a painter thread, so it needs no lock. It does not repaint while a single system call blocks.

- The activity indicator shows elapsed time, and the scan's match count. Removal shows a progress bar over targets, plus bytes when sizes were measured. Scanning has no bar: its only cheap total, the root's top-level entries, stalls on one large subtree. Removal reports each path inside a directory target, so the indicator keeps repainting during a large removal.

- After removal, oclean reports the bytes freed: a `Removed N item(s), SIZE.` line in text output, and `freed_size` in the JSON `summary`. Bytes are summed as files are unlinked, so they are exact, exclude failed removals, and need no `--stats` walk.

- Sizes are shown in decimal units (KB, MB, GB, TB; 1 KB = 1000 bytes) instead of binary units (KiB, MiB), so they match Finder. This changes `--stats` output and the JSON `*_size_human` fields.

- The global config file honours `XDG_CONFIG_HOME`: it is `$XDG_CONFIG_HOME/oclean/config.toml` when that is absolute, else `~/.config/oclean/config.toml`.

- The `common` and `python` presets, and so the defaults, leave out `.bash_history` and `.python_history`, which hclean 0.1.0 included. Shell and REPL history is user data that nothing rebuilds; remove it with `-g '**/.bash_history'` if wanted.

- CI runs `make test` on Ubuntu 24.04 with its packaged OCaml 4.14.1, and on macOS with OCaml 5.

- `-B` looks for `.git` only up to the home directory, not in `~` or above it. A home directory kept under git (dotfiles) would otherwise qualify every project beneath it.

- Bare `-c` stops its upward search below the home directory, so a `.oclean.toml` in `~` or above it is never read. Such a file would apply to every run under `~`, which is the global file's role.

- The confirmation prompt is written to stderr and states the item count. Before, a prompt on stdout corrupted JSON output.
