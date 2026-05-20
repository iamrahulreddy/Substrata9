# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

## [Unreleased]

No pending changes.

---

## [1.3.1] - 2026-05-20

### Added
- Container-aware memory resolution using cgroup v1 (`memory.limit_in_bytes`) and v2 (`memory.max`) to report accurate available RAM inside containers instead of leaking host-level `/proc/meminfo` values.
- GPU PID-namespace detection: `s9-gpu`, `s9-inspect`, and `s9-anomaly` now identify when `nvidia-smi` reports a container proxy PID (such as `dumb-init` at PID 1) and tag the result with `pid_scope: container_proxy` and a descriptive note field.
- Aggregate GPU memory field (`gpu_memory_used_mb`) in GPU-aware JSON output for reliable GPU telemetry even when per-process PID attribution is unavailable.
- Cross-platform validation across Tesla T4 (Colab), A100 40 GB (Lightning AI), and H100 80 GB (Modal Firecracker) with 18/18 stages and 0 red flags on each run.

### Changed
- Cloud/GPU validation treats `jq`, `shellcheck`, `bc`, `zip`, and `nvidia-smi` as optional unless explicitly required by the runner environment.
- Heavy GPU stress allocation is now adaptive and chunked, with configurable caps (`S9_HEAVY_GPU_FRACTION`, `S9_HEAVY_GPU_MAX_MB`, `S9_HEAVY_GPU_MIN_MB`), replacing the previous single-tensor approach.
- Load-induced latency slowdown is now a warning by default; strict failure gating requires `S9_FAIL_ON_PERF_SLOWDOWN=1`.
- Static audit scans expanded to include extensionless shell entrypoints in `bin/` and example scripts.
- Test suites now report skipped checks separately from passed checks, with `S9_FAIL_ON_SKIP=1` available for strict release gating.

### Fixed
- Removed stale packaging-helper references from release notes and ignore comments so the source tree reflects the current shipped files.
- Removed hardcoded `/tmp` paths from example scripts; all temp output now respects `TMPDIR`.
- Removed spurious `bc` dependency from example scripts.

---

## [1.3.0] - 2026-05-19

### Added
- **`s9-gpu` tool** — Optional NVIDIA GPU process visibility using `nvidia-smi` to map GPU memory to specific Linux processes.
- **Auto JSON Export** — Added `-e` / `--export-json` flag to all tools, saving output to an auto-generated timestamped file with the local timezone suffix (e.g. `s9-inspect_2026-05-16_19-30-00_UTC.json`).
- **Comprehensive test gating** — Introduced cloud-oriented test coverage with dependency checking, bash syntax checking, ShellCheck, JSON validation, resource leak detection, concurrency stress, and heavy workload testing under GPU load.
- **Controlled stress testing** — Added real PyTorch CUDA workloads and a deterministic Bash loop creating 80+ file descriptors to validate parsing under pressure.

### Changed
- **Performance polish** — Eliminated hundreds of subshell forks to `bc` and `awk` by implementing native Bash integer math `(( ... ))` for percentage logic, drastically speeding up all tools on busy servers.
- **CLI Hygiene** — Removed confusing `-v`/`--version` flags from all tools to avoid ambiguity with external driver versions (version string remains visible in `--help`).
- **Signal decoding clarity** — Documented the intentional truncation of 64-bit masks from `/proc/` to 32 bits to parse standard POSIX signals.
- **JSON regex generation** — Tightened number formatting in `s9_json_kv` so values with leading zeros (e.g. PID `007`) are correctly emitted as JSON strings, avoiding invalid types.
- **Test robustness** — Massively expanded the test suite from ~60 to 462 assertions covering GPU mocking, snapshot uniqueness, leading zeros, and strict JSON schema validation.

### Fixed
- **Orphan miscalculation** — Fixed `s9-anomaly --quiet` mode, applying the correct system-daemon filter and kernel thread exclusion to prevent inflated orphan counts.
- **Trap clobbering** — Replaced brittle inline traps with reliable `cleanup()` functions in `s9-fdmap` and `s9-compare` to prevent overwritten `EXIT` handlers.
- **Math Fallback** — Patched the bundled `bin/bc` to correctly parse multi-character operators (`==`, `<=`, `!=`) under Bash 5.1+, preventing random script failures.
- **Division by zero** — Added safeguards to memory percentage logic across the codebase to handle unreadable `/proc/meminfo` gracefully.
- **JSON commas** — Corrected the index tracking in `s9-anomaly` to emit valid JSON without trailing commas during selective flag execution.
- **Multiple positional arguments** — Fixed `s9-inspect` to explicitly reject multiple PIDs/names, preventing hidden errors.
- **Container parsing** — Removed experimental namespace detection from `s9-inspect` and `s9-tree` that caused hangs and inaccurate JSON.
- **Security hardening** — Removed `--env` flag from `s9-inspect` to prevent sensitive environment variable exposure.

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
| Unreleased | — | Pending changes |
| 1.3.1 | 2026-05-20 | Container-aware memory/GPU, cross-platform validation (T4/A100/H100), adaptive stress |
| 1.3.0 | 2026-05-19 | Performance polish, GPU visibility, Auto JSON export, Subshell elimination |
| 1.2.1 | 2026-05-10 | JSON validity, CLI guards, safer snapshots, test wiring |
| 1.2.0 | 2026-01-02 | Bug fixes, improved container detection, documentation |
| 1.1.0 | 2025-12-05 | Process comparison, test improvements |
| 1.0.0 | 2025-11-01 | Initial release with 5 core tools |
