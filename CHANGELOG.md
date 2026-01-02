# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

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

## [Unreleased]

### Added
- Enhanced test suite with 60+ unit tests covering edge cases and error handling
- CI/CD documentation with GitHub Actions workflow example
- Performance guidelines for production vs. diagnostic use

### Changed
- Improved CRLF handling for cross-platform compatibility
- Refined documentation with clearer explanations

### Fixed
- Truncated code block in USAGE.md

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
| 1.2.0 | 2026-01-02 | Bug fixes, improved container detection, documentation |
| 1.1.0 | 2025-12-05 | Process comparison, test improvements |
| 1.0.0 | 2025-11-01 | Initial release with 5 core tools |
