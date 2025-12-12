# Substrata9 Architecture

Technical overview of the toolkit's design, data flow, and internal structure.

> 🎬 **Want to see these tools in action?** Check the [animated demos](../README.md#-demo) or browse `GIFS/`.

---

## Overview

Substrata9 interfaces directly with the Linux `/proc` filesystem to extract process information. This provides the same data source used by `ps`, `top`, and similar tools, with full control over extraction and presentation.

Here's the high-level structure:

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Space                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Tools (bin/)                    Library (lib/)                 │
│   ┌─────────────┐                ┌─────────────────┐             │
│   │ s9-inspect  │───────────────▶│                 │            │
│   │ s9-tree     │───────────────▶│  s9-common.sh   │            │
│   │ s9-fdmap    │───────────────▶│                 │            │
│   │ s9-snapshot │───────────────▶│  Colors, I/O,   │            │
│   │ s9-anomaly  │───────────────▶│  Formatting,    │            │
│   └─────────────┘                │  /proc helpers  │            │
│         │                        └─────────────────┘            │
│         │                                                        │
│         ▼                                                        │
├─────────────────────────────────────────────────────────────────┤
│                      /proc Filesystem                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   /proc/[pid]/status    → Process state, memory, threads        │
│   /proc/[pid]/fd/       → Open file descriptors                 │
│   /proc/[pid]/maps      → Memory regions                        │
│   /proc/[pid]/io        → I/O statistics                        │
│   /proc/[pid]/cmdline   → Command line arguments                │
│   /proc/[pid]/environ   → Environment variables                 │
│   /proc/[pid]/limits    → Resource limits                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Linux Kernel                              │
│                                                                  │
│   Process table, memory management, file descriptor tables...   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

The kernel maintains all this information internally. When you read `/proc/1234/status`, the kernel generates the text on the fly from its internal `task_struct`. There's no file on disk—it's synthesized when you ask for it.

---


## Core Library: `s9-common.sh`

All tools share a common library to avoid code duplication across color definitions, error handling, and parsing helpers.

Every tool loads it at startup:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/s9-common.sh"
s9_init  # Validates environment, sets up colors
```

Here's what the library handles:

| Category | Functions | What They Do |
|----------|-----------|--------------|
| **Output** | `s9_die`, `s9_warn`, `s9_info` | Consistent error messages with colors |
| **Formatting** | `s9_human_bytes`, `s9_human_kb` | Turn "12345678" into "11.8 MB" |
| **Process Data** | `s9_get_rss`, `s9_get_state`, `s9_get_ppid` | Extract fields from /proc without repeating grep/awk everywhere |
| **Safety** | `s9_sanitize_filename`, `s9_read_proc_file` | Handle edge cases without crashing |
| **JSON** | `s9_json_kv`, `s9_sanitize_json` | Generate valid JSON for `--json` output |

The library is loaded via `source` rather than as a subprocess. This executes in the current shell context, making variables available to the calling script without fork overhead.

---


## Tool Internals

Detailed breakdown of each tool's operation.


### s9-inspect

Deep inspection of a single process. Accepts a PID or process name.

**Data Flow:**

```
User Input (PID or name)
        │
        ▼
┌───────────────────┐
│  s9_resolve_pid   │  ← Convert name to PID, validate it exists
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Read /proc files │
│                   │
│  • status         │  ← State, memory, threads, UIDs
│  • cmdline        │  ← Command line arguments
│  • exe            │  ← Path to executable
│  • fd/            │  ← Open file descriptors
│  • limits         │  ← Resource limits
│  • io             │  ← I/O statistics (requires root)
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Format & Output  │  ← Colorize, align, add headers
└───────────────────┘
```

Implementation notes:

- Signal masks in `/proc/[pid]/status` are hex bitmasks, decoded to signal names via lookup table.
- FD types are determined by reading symlink targets in `/proc/[pid]/fd/`. Sockets appear as `socket:12345`, pipes as `pipe:12345`.
- Memory percentages are calculated against total system memory from `/proc/meminfo`.


### s9-tree

Process hierarchy visualization. Shows parent-child relationships.

```
Phase 1: Collection
┌─────────────────────────────────────────┐
│  for each /proc/[0-9]* directory:       │
│    • Read status file                   │
│    • Extract: PID, PPID, Name, State    │
│    • Store in associative arrays        │
└─────────────────────────────────────────┘
                    │
                    ▼
Phase 2: Build Adjacency List
┌─────────────────────────────────────────┐
│  for each process:                      │
│    • Add PID to parent's children list  │
│    • children[PPID] += PID              │
└─────────────────────────────────────────┘
                    │
                    ▼
Phase 3: Render (DFS)
┌─────────────────────────────────────────┐
│  print_tree(pid, depth, prefix):        │
│    • Print current process with indent  │
│    • For each child:                    │
│      • Recurse with increased depth     │
│      • Use └── or ├── based on position │
└─────────────────────────────────────────┘
```

Uses Bash associative arrays (hash maps) for O(1) lookups:

```bash
declare -A proc_name    # proc_name[1234]="nginx"
declare -A proc_ppid    # proc_ppid[1234]="1"
declare -A children     # children[1]="234 567 890"
```

Without hash maps, each lookup would require O(n) scans. On systems with 500+ processes, this becomes significant.


### s9-fdmap

System-wide file descriptor analysis. Identifies potential FD leaks by scanning all processes.

```
┌─────────────────────────────────────────┐
│  Scan all /proc/[0-9]*/fd/ directories  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  For each process:                      │
│    • Count entries in fd/               │
│    • Categorize by type:                │
│      - socket: → sockets                │
│      - pipe:   → pipes                  │
│      - /dev/*  → devices                │
│      - /*      → regular files          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Apply thresholds for leak detection    │
│  Sort by FD count                       │
│  Output summary or detailed view        │
└─────────────────────────────────────────┘
```

**Leak Detection Heuristics:**

A process with 1000+ file descriptors is suspicious. But context matters:
- A web server might legitimately have many sockets
- A database might have many open data files

The tool flags high counts and lets the user investigate further with `s9-inspect`.


### s9-snapshot

Captures process state for later comparison. Useful for identifying memory leaks by comparing state before and after a workload.

**Storage Format:**

Snapshots are stored as simple text files:

```
~/.substrata9/snapshots/{name}_{pid}_{timestamp}.snap
```

Each snapshot contains key metrics in a parseable format:

```
# Snapshot: baseline
# PID: 1234
# Timestamp: 2025-01-15 10:30:00
VmRSS: 12345 kB
VmSize: 67890 kB
Threads: 4
FDCount: 47
...
```

**Diff Algorithm:**

```
┌─────────────────┐     ┌─────────────────┐
│  Snapshot A     │     │  Snapshot B     │
│  (before)       │     │  (after)        │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Calculate deltas:    │
         │  • RSS: +1024 kB      │
         │  • FDs: +5            │
         │  • Threads: +2        │
         └───────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Color-code by        │
         │  severity:            │
         │  • >10% growth = red  │
         │  • >5% = yellow       │
         │  • else = green       │
         └───────────────────────┘
```


### s9-anomaly

System-wide health check that identifies common issues.

**Checks Performed:**

| Check | How It Works |
|-------|--------------|
| **Zombies** | Scan for processes with state `Z` in `/proc/[pid]/status` |
| **Memory Hogs** | Compare RSS to total system memory, flag if above threshold |
| **FD Hogs** | Count FDs per process, flag if above threshold |
| **D-State** | Find processes stuck in uninterruptible sleep (often I/O issues) |
| **Orphans** | Find user processes whose parent is PID 1 (got adopted by init) |

Uses `set -uo pipefail` instead of `set -euo pipefail`. The `-e` flag exits on any error, but when scanning `/proc`, processes can terminate between listing and reading. This approach handles race conditions gracefully rather than crashing.

---


## Design Decisions

| Decision | Rationale | Trade-off |
|----------|-----------|----------|
| **Pure Bash** | Zero dependencies, runs anywhere, educational | Slower than C/Go/Rust |
| **Direct /proc access** | Source of truth, no dependency on `ps`/`top` | Kernel changes could break parsing |
| **Associative arrays** | O(1) lookups for tree building | Requires Bash 4.0+ |
| **Text snapshots** | Human-readable, easy to debug | Not efficient for high-frequency capture |
| **No external dependencies** | Works on minimal systems | Can't use `jq` for JSON parsing internally |


### Language Choice

- **Python:** Not always available on minimal systems or containers.
- **Go/Rust:** Requires compilation. Harder to audit.
- **Bash:** Available everywhere, easy to read, acceptable performance for interactive debugging.


### Why Direct /proc Access

- `ps` output format varies between systems (GNU vs BSD)
- Avoids additional dependencies
- Provides access to data `ps` doesn't expose (signal masks, detailed limits)

---


## Error Handling

### Race Conditions

Processes can exit at any moment. Between listing `/proc/[0-9]*` and reading `/proc/1234/status`, that process may terminate. Handled as follows:

```bash
# Pattern used throughout the codebase
for proc_dir in /proc/[0-9]*; do
    [[ -r "$proc_dir/status" ]] || continue  # Skip if unreadable
    content=$(cat "$proc_dir/status" 2>/dev/null) || continue  # Skip if read fails
    # ... process content ...
done
```


### Permission Handling

Many `/proc` files require root access. The approach:

1. Attempt to read the file
2. On failure, display informative message
3. Continue with available data

```bash
if [[ -r "/proc/$pid/io" ]]; then
    # Parse I/O stats
else
    s9_warn "Cannot read I/O stats (requires root)"
fi
```


### Input Validation

User input is sanitized before use:

```bash
# Only allow safe characters in process names
sanitized="${input//[^a-zA-Z0-9_.-]/}"

# Validate PIDs are numeric
[[ "$pid" =~ ^[0-9]+$ ]] || s9_die "Invalid PID: $pid"
```

---


## Future Directions

Planned enhancements:

| Feature | Status | Notes |
|---------|--------|-------|
| **eBPF integration** | Exploring | Would enable event-driven monitoring |
| **Plugin system** | Planned | Custom parsers for specific `/proc` files |
| **TUI mode** | Considering | Interactive terminal UI like `htop` |
| **Prometheus exporter** | Considering | Export metrics for monitoring systems |

---


## Contributing

Guidelines for adding or modifying tools:

1. **Source the common library** — don't duplicate functionality
2. **Handle errors gracefully** — assume processes can disappear
3. **Support `--json` output** — makes scripting possible
4. **Add `--help`** — standard CLI convention

See [CONTRIBUTING.md](../CONTRIBUTING.md) for more.

---

*Part of Substrata9 — Linux Process Archaeology Toolkit*
