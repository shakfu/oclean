# Changelog

All notable changes to oclean are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First version: a port of hclean 0.1.0 to OCaml, using only the standard library and `unix`. Options, presets, the config file format and the output formats are unchanged. The config file is `.oclean.toml`, with `~/.config/oclean/config.toml` as the global fallback, so oclean and rclean settings do not interfere. See [README.md](README.md#differences-from-hclean) for the hclean defects fixed in the port.

- Globs are compiled once into a pattern tree. A segment with no metacharacters is compared as a string, and `**/x` is matched as the basename pattern `x`. The `--preset all` scan of a 237k-entry tree took 7.3 s before these fast paths and takes 1.4 s with them.

- The activity indicator repaints from the scan loop instead of a painter thread, so it needs no lock. It does not repaint while a single system call blocks.

- The confirmation prompt is written to stderr and states the item count. Before, a prompt on stdout corrupted JSON output.
