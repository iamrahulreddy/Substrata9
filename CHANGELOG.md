# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

## [Unreleased]

### Planned
- **Styling & linting:** Apply ShellCheck-driven style and robustness
	fixes in a future maintenance commit (traps quoting, safe `printf`
	formats, avoid parsing `ls`, and other non-functional improvements).
- **GPU process visibility:** Add GPU-aware process diagnostics using
	`nvidia-smi` where available, with room for other vendor backends later.

---

## [1.2.1] - 2026-05-10

### Fixed
- **JSON validity** — Corrected malformed JSON in `s9-fdmap` file/socket/leak modes and selective `s9-anomaly --json` checks.
- **JSON export streams** — Moved export status messages for JSON output to stderr so stdout remains parseable.
- **CLI help/version behavior** — Deferred Linux, `/proc`, and `bc` checks until after `--help` and `--version` are handled.
- **Argument validation** — Added friendly errors for options missing required values such as `--top`, `--pid`, `--export`, and `--name`.
- **Snapshot safety** — Moved snapshot directory creation out of read-only commands and replaced `ls | xargs rm` deletion with quoted array-based removal.
- **Process stat parsing** — Added safe `/proc/[pid]/stat` field extraction so process names containing spaces or parentheses do not corrupt age/start-time calculations.
- **Socket lookup coverage** — Added IPv6 socket scans via `/proc/net/tcp6` and `/proc/net/udp6`.
- **Safe directory validation** — Tightened HOME path boundary checks for custom snapshot directories.
- **Tree JSON guard** — `s9-tree --json --user` now fails clearly instead of emitting concatenated JSON objects.
- **Bundled calculator fallback** — Project math now calls the repo-local `bin/bc` through Bash when system `bc` is absent, so a missing executable bit no longer breaks tests.
- **Compare helper execution** — `s9-compare` can invoke its sibling `s9-snapshot` through Bash when executable bits are missing.
- **USAGE rendering** — Fixed a truncated code block in the usage guide.

### Added
- Enhanced test coverage for JSON validity, CLI argument handling, and edge cases.
- GitHub Actions CI plus issue and pull request templates.
- Cross-platform `.gitattributes` rules for shell scripts, extensionless Bash tools, docs, and binary assets.
- Production and diagnostic performance guidance in the documentation.

### Changed
- `make test` now runs the full shell test runner in `tests/run_tests.sh`.
- Test scripts and the temporary verifier invoke tools through Bash to avoid cascading permission errors while still reporting missing release executable bits.
- The temporary verifier normalizes executable bits for shell entrypoints and forces ANSI colors when launched from a color-capable terminal.
- JSON documentation now matches the emitted field names and snapshot diff shape.
- Documentation was refined with clearer setup, usage, troubleshooting, and CI guidance.
- Bundled `bin/` scripts were marked executable so tools are runnable immediately after checkout.

## [1.2.0] - 2026-01-02

### Fixed
- **Signal decoding** — Correctly handles hex masks from /proc without 0x prefix
- **Empty-data crash** — `debug_memory_leak.sh` now validates samples before analysis
- **PID validation** — `find_fd_leak.sh` handles empty auto-selection gracefully
- **Temp file cleanup** — `s9-fdmap` now properly cleans up temp files on exit/interrupt
- **Percentage formatting** — Fixed regex pattern for decimal detection in comparisons
- **Alert timing** — `debug_memory_leak.sh` alerts fire at correct intervals (10, 20, 30...)
- **JSON sanitization** — Added handling for form feed, backspace, and control characters
- **Path validation** — Uses `realpath` for proper symlink resolution and writability checks

### Added
- **Container detection** — Support for containerd, podman, and PID namespace detection
- **Test runner checks** — Validates library and /proc availability before running tests
- **Documentation** — Added missing `--quiet` and `--export` flags to USAGE.md

### Changed
- Architecture diagram now includes `s9-compare` tool
- Improved namespace detection using PID namespace (most reliable indicator)

---

## [1.1.0] - 2025-12-05

### Added
- `s9-compare` — Side-by-side comparison of two live processes
- `--force` flag for non-interactive snapshot deletion
- Comprehensive JSON output for all tools

### Changed
- Improved snapshot diff output with detailed resource comparison
- Enhanced error messages with actionable suggestions

### Fixed
- Race condition handling when processes exit during inspection
- Signal mask decoding for edge cases

---

## [1.0.0] - 2025-11-01

Initial public release.

### Core Tools

| Tool | Purpose |
|------|---------|
| `s9-inspect` | Deep single-process inspection with memory, FD, and signal analysis |
| `s9-tree` | Process hierarchy visualization with resource usage |
| `s9-fdmap` | System-wide file descriptor mapping and leak detection |
| `s9-snapshot` | Process state capture with temporal comparison |
| `s9-anomaly` | Automated detection of zombies, resource hogs, and unusual states |

### Features
- **Zero dependencies** — Pure Bash implementation using only standard Linux utilities
- **JSON output** — Machine-readable output for automation and integration
- **Color-coded display** — Terminal-aware formatting with graceful degradation
- **Safe by design** — Input sanitization, path validation, no `eval` usage

### Documentation
- Comprehensive usage guide with examples
- Architecture documentation for contributors
- JSON schema reference
- Troubleshooting guide

---

## Version Summary

| Version | Date | Highlights |
|---------|------|------------|
| 1.2.1 | 2026-05-10 | JSON validity, CLI guards, safer snapshots, test wiring |
| 1.2.0 | 2026-01-02 | Bug fixes, improved container detection, documentation |
| 1.1.0 | 2025-12-05 | Process comparison, test improvements |
| 1.0.0 | 2025-11-01 | Initial release with 5 core tools |
