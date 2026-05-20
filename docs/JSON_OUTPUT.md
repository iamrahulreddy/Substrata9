# JSON Output Reference

All Substrata9 tools support `--json` output for integration with scripts, dashboards, and automation pipelines. This document covers the JSON schemas for each tool.


## Quick Start

Add `--json` to any command to get machine-readable output:

```bash
# Instead of pretty-printed text...
s9-inspect 1234

# ...get JSON you can pipe to other tools
s9-inspect 1234 --json
```

Recommended: use [`jq`](https://stedolan.github.io/jq/) for parsing and filtering:

```bash
# Get just the RSS memory
s9-inspect 1234 --json | jq '.rss_kb'

# Find processes using more than 100MB
s9-tree --json | jq '.children[] | select(.rss_kb > 102400) | .name'
```

## s9-inspect

Returns detailed information about a single process.

**When to use:** You need programmatic access to process details for alerting, logging, or automation.


### Schema

```json
{
  "pid": 1234,
  "name": "nginx",
  "state": "S",
  "ppid": 1,
  "uid": 33,
  "user": "www-data",
  "threads": 1,
  "exe": "/usr/sbin/nginx",
  "cwd": "/var/www/html",
  "cmdline": "nginx: worker process",

  "vm_size_kb": 10240,
  "rss_kb": 5120,
  "fd_count": 12,
  "io_read_chars": 1000,
  "io_write_chars": 2000,

  "gpu_available": false,
  "gpu_pid": null,
  "gpu_process_name": "",
  "gpu_index": "",
  "gpu_name": "",
  "gpu_memory_mb": 0,
  "gpu_pid_scope": "",
  "gpu_process_type": "",
  "gpu_memory_used_mb": 0
}
```


### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name (from `/proc/[pid]/comm`) |
| `state` | string | Single-character process state code (for example, "S") |
| `ppid` | number | Parent process ID |
| `uid` | number | User ID of process owner |
| `user` | string | Username of process owner |
| `threads` | number | Number of threads |
| `exe` | string | Path to executable |
| `cwd` | string | Current working directory |
| `cmdline` | string | Full command line |

| `vm_size_kb` | number | Virtual memory size in kilobytes |
| `rss_kb` | number | Resident set size (physical memory) in kilobytes |
| `fd_count` | number | Number of open file descriptors |
| `io_read_chars` | number | Characters read from `/proc/[pid]/io` (requires permission) |
| `io_write_chars` | number | Characters written from `/proc/[pid]/io` (requires permission) |

| `gpu_available` | boolean | Whether nvidia-smi is present and functional |
| `gpu_pid` | number/null | PID as reported by nvidia-smi, or null if the inspected process is not directly mapped |
| `gpu_process_name` | string | Process name reported by nvidia-smi |
| `gpu_index` | number/string | GPU index (empty string if not using GPU) |
| `gpu_name` | string | GPU model name |
| `gpu_memory_mb` | number | GPU memory allocated in MB |
| `gpu_pid_scope` | string | PID attribution status: `visible`, `host`, `container_proxy`, `name_mismatch`, `unknown`, or empty |
| `gpu_process_type` | string | GPU process type (e.g. "compute") |
| `gpu_memory_used_mb` | number | Total GPU memory currently reported by nvidia-smi across visible GPUs |
| `gpu_note` | string | Optional note when GPU memory exists but exact local PID attribution is unavailable |


### Example Queries

```bash
# Get memory usage in MB
s9-inspect nginx --json | jq '.rss_kb / 1024'



# Get all fields as key=value pairs
s9-inspect 1234 --json | jq -r 'to_entries | .[] | "\(.key)=\(.value)"'
```

## s9-tree

Returns a recursive tree structure representing the process hierarchy.

**When to use:** You need to analyze parent-child relationships programmatically, or build a visualization.

`s9-tree --json` emits the tree rooted at the selected PID. User filtering is intentionally limited to text output for now; use `jq` to filter JSON output by the `user` field.

### Schema

```json
{
  "pid": 1,
  "name": "systemd",
  "state": "S",
  "rss_kb": 12345,
  "user": "root",
  "threads": 1,

  "children": [
    {
      "pid": 100,
      "name": "systemd-journald",
      "state": "S",
      "rss_kb": 5678,
      "user": "root",
      "threads": 1,

      "children": []
    },
    {
      "pid": 200,
      "name": "sshd",
      "state": "S",
      "rss_kb": 3456,
      "children": [
        {
          "pid": 201,
          "name": "sshd",
          "state": "S",
          "rss_kb": 4567,
          "children": [
            {
              "pid": 202,
              "name": "bash",
              "state": "S",
              "rss_kb": 2345,
              "children": []
            }
          ]
        }
      ]
    }
  ]
}
```


### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `state` | string | Single-character state code (R, S, D, Z, T) |
| `rss_kb` | number | Resident memory in kilobytes |
| `user` | string | Process owner |
| `threads` | number | Number of threads |

| `children` | array | Array of child process objects (recursive) |


### Example Queries

```bash
# Get all process names in the tree (flattened)
s9-tree --json | jq '.. | .name? // empty'

# Find all processes with more than 100MB RSS
s9-tree --json | jq '.. | select(.rss_kb? and .rss_kb > 102400) | {name, pid, rss_kb}'

# Count total processes in tree
s9-tree --json | jq '[.. | .pid? // empty] | length'

# Get direct children of PID 1
s9-tree --json | jq '.children[] | {name, pid}'
```

## s9-fdmap

Returns file descriptor information, either as a summary or search results.

**When to use:** You're building FD monitoring, leak detection alerts, or need to find which process has a file open.


### Summary Mode Schema

When run without search options:

```json
{
  "summary": [
    {
      "pid": 1234,
      "name": "nginx",
      "fd_count": 1024,
      "user": "www-data"
    },
    {
      "pid": 5678,
      "name": "mysql",
      "fd_count": 512,
      "user": "mysql"
    }
  ],
  "stats": {
    "total_processes": 150,
    "total_fds": 5000,
    "system_allocated": 5000,
    "system_max": 100000
  }
}
```


### Field Reference (Summary)

**summary array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `fd_count` | number | Number of open file descriptors |
| `user` | string | Process owner |

**stats object:**

| Field | Type | Description |
|-------|------|-------------|
| `total_processes` | number | Number of processes scanned |
| `total_fds` | number | Total FDs across all processes |
| `system_allocated` | number | System-wide allocated FDs |
| `system_max` | number | System-wide FD limit |


### Example Queries

```bash
# Get top 5 FD consumers
s9-fdmap --json | jq '.summary | sort_by(.fd_count) | reverse | .[0:5]'

# Find processes with more than 500 FDs
s9-fdmap --json | jq '.summary[] | select(.fd_count > 500)'

# Calculate FD usage percentage
s9-fdmap --json | jq '.stats | ((.total_fds / .system_max) * 100) | round'
```

## s9-anomaly

Returns arrays of detected anomalies, organized by type.

**When to use:** Building health monitoring, alerting on zombies or resource hogs, or integrating with incident management.


### Schema

```json
{
  "zombies": [
    {
      "pid": 123,
      "name": "defunct_proc",
      "ppid": 100,
      "parent_name": "bad_parent",
      "age": "10m"
    }
  ],
  "hogs": [
    {
      "pid": 456,
      "name": "leak_app",
      "rss_kb": 999999,
      "rss_percent": 45.2,
      "fd_count": 2000,
      "issues": "HIGH-MEM HIGH-FDS"
    }
  ],
  "unusual_states": [
    {
      "pid": 789,
      "name": "stuck_io",
      "state": "D",
      "state_desc": "disk sleep"
    }
  ],
  "orphans": [
    {
      "pid": 321,
      "name": "orphan_worker",
      "ppid": 1,
      "user": "www-data",
      "command": "/usr/bin/orphan_worker"
    }
  ],
  "gpu": [
    {
      "pid": 1,
      "name": "/bin/dumb-init",
      "gpu_index": 0,
      "gpu_name": "NVIDIA H100 80GB HBM3",
      "gpu_memory_mb": 4096,
      "pid_scope": "container_proxy",
      "gpu_process_type": "compute"
    }
  ],
  "gpu_available": true,
  "gpu_memory_used_mb": 4096,
  "gpu_attribution": "container_proxy",
  "gpu_note": "nvidia-smi reports GPU memory against a container-visible proxy PID; local workload PID mapping may be unavailable"
}
```


### Field Reference

**zombies array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Zombie process ID |
| `name` | string | Process name |
| `ppid` | number | Parent PID (who should reap it) |
| `parent_name` | string | Parent process name |
| `age` | string | How long it's been a zombie |

**hogs array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `rss_kb` | number | Memory usage in KB |
| `rss_percent` | number | Percentage of system memory |
| `fd_count` | number | Number of open FDs |
| `issues` | string | Space-separated issue flags (HIGH-MEM, HIGH-FDS) |

**unusual_states array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `state` | string | State code (D, T, etc.) |
| `state_desc` | string | Human-readable state description |

**orphans array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `ppid` | number | Current parent PID, usually 1 for adopted processes |
| `user` | string | Process owner |
| `command` | string | Command line, when available |

**gpu array:**

| Field | Type | Description |
|-------|------|-------------|
| `pid` | number | Process ID |
| `name` | string | Process name |
| `gpu_index` | number | Physical GPU index |
| `gpu_name` | string | GPU model name |
| `gpu_memory_mb` | number | GPU memory allocated in MB |
| `pid_scope` | string | Local PID attribution status: `visible`, `host`, `container_proxy`, `name_mismatch`, or `unknown` |
| `gpu_process_type` | string | GPU process type (e.g. "compute") |

**GPU top-level fields:**

| Field | Type | Description |
|-------|------|-------------|
| `gpu_available` | boolean | Whether `nvidia-smi` is installed and returning data |
| `gpu_memory_used_mb` | number | Total GPU memory currently reported by nvidia-smi across visible GPUs |
| `gpu_attribution` | string | Optional attribution mode, currently `container_proxy` when nvidia-smi reports memory against PID 1 or an init wrapper |
| `gpu_note` | string | Optional explanation when exact per-process mapping is unavailable |


### Example Queries

```bash
# Check if any zombies exist
s9-anomaly --json | jq 'if (.zombies | length) > 0 then "ALERT: Zombies found!" else "OK" end'

# Get all hog PIDs for further investigation
s9-anomaly --json | jq '.hogs[].pid'

# Count issues by type
s9-anomaly --json | jq '{zombies: (.zombies | length), hogs: (.hogs | length), stuck: (.unusual_states | length)}'

# Find memory hogs using more than 50% RAM
s9-anomaly --json | jq '.hogs[] | select(.rss_percent > 50)'
```

## s9-snapshot

Returns status information for capture operations and comparison results for diffs.

**When to use:** Automating snapshot workflows, building memory leak detection pipelines.


### Capture Response Schema

```json
{
  "status": "success",
  "file": "/home/user/.substrata9/snapshots/baseline_1234_20250115.snap",
  "name": "baseline",
  "pid": 1234,
  "timestamp": "2025-01-15 12:00:00"
}
```


### Diff Response Schema

```json
{
  "before": "baseline_1234_20250115_120000.snap",
  "after": "after_load_1234_20250115_130000.snap",
  "pid1": 1234,
  "pid2": 1234,
  "memory": {
    "rss_before_kb": 10240,
    "rss_after_kb": 15360,
    "rss_diff_kb": 5120,
    "vmsize_before_kb": 102400,
    "vmsize_after_kb": 153600,
    "vmsize_diff_kb": 51200,
    "vmswap_before_kb": 0,
    "vmswap_after_kb": 0
  },
  "resources": {
    "fd_before": 100,
    "fd_after": 150,
    "fd_diff": 50,
    "threads_before": 4,
    "threads_after": 8,
    "threads_diff": 4
  },
  "assessment": {
    "memory_status": "moderate_growth",
    "fd_status": "moderate_growth",
    "threads_status": "stable",
    "rss_diff_kb": 5120,
    "fd_diff": 50,
    "threads_diff": 0
  }
}
```


### Field Reference (Diff)

**assessment object:**

| Field | Type | Values | Description |
|-------|------|--------|-------------|
| `memory_status` | string | "stable", "moderate_growth", "critical_growth", "significant_decrease" | Memory growth assessment |
| `fd_status` | string | "stable", "moderate_growth", "critical_growth" | FD growth assessment |
| `threads_status` | string | "stable", "significant_change" | Thread growth assessment |
| `rss_diff_kb` | number | RSS delta in kilobytes |
| `fd_diff` | number | File descriptor count delta |
| `threads_diff` | number | Thread count delta |


### Example Queries

```bash
# Check if memory grew significantly
s9-snapshot diff baseline after_load --latest --json | jq '.assessment.memory_status'

# Get memory growth in MB
s9-snapshot diff baseline after_load --latest --json | jq '.memory.rss_diff_kb / 1024'

# Alert if memory status is critical
s9-snapshot diff baseline after_load --latest --json | jq 'if .assessment.memory_status == "critical_growth" then "ALERT!" else "OK" end'
```

## s9-compare

`s9-compare --json` emits the same comparison schema as `s9-snapshot diff --json`. It creates temporary snapshots for the two live process targets, compares them, and removes the temporary snapshot directory when the command exits.

```bash
s9-compare 1234 5678 --json | jq '.resources'
```

## s9-gpu

Returns process and NVIDIA GPU memory mapping.

**When to use:** Creating metrics for GPU utilization per process or auditing workloads.

### Schema

```json
{
  "gpu_available": true,
  "count": 1,
  "processes": [
    {
      "pid": 5678,
      "name": "python3",
      "gpu_index": 0,
      "gpu_name": "Tesla T4",
      "gpu_memory_mb": 4096,
      "pid_scope": "visible",
      "gpu_process_type": "compute"
    }
  ],
  "gpu_memory_used_mb": 4096
}
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `gpu_available` | boolean | True if nvidia-smi is installed and returning data |
| `count` | number | Total number of GPU processes returned |
| `processes` | array | Array of process objects |
| `pid` | number | Process ID (inside processes array) |
| `name` | string | Process name (inside processes array) |
| `gpu_index` | number | Physical GPU index (inside processes array) |
| `gpu_name` | string | GPU model name (inside processes array) |
| `gpu_memory_mb` | number | GPU memory allocated in MB (inside processes array) |
| `pid_scope` | string | Local PID attribution status: `visible`, `host`, `container_proxy`, `name_mismatch`, or `unknown` |
| `gpu_process_type` | string | GPU process type, e.g. "compute" or "graphics" (inside processes array) |
| `gpu_memory_used_mb` | number | Total GPU memory currently reported by nvidia-smi across visible GPUs |
| `attribution` | string | Optional top-level attribution mode, currently `container_proxy` when nvidia-smi reports memory against PID 1 or an init wrapper |
| `note` | string | Optional explanation when exact per-process mapping is unavailable |

In containers, `nvidia-smi` can report GPU memory against a host PID or a container-visible proxy such as PID 1. In that case `gpu_memory_used_mb` is the safer aggregate signal, while per-process rows should be treated as best-effort attribution.

## Tips for Working with JSON Output

### Handling Missing Fields

Some fields may be missing if data isn't available (e.g., I/O stats without root):

```bash
# Use // to provide defaults
s9-inspect 1234 --json | jq '.io_read_chars // "N/A"'
```


### Combining with Other Tools

```bash
# Send to a monitoring system
s9-anomaly --json | curl -X POST -H "Content-Type: application/json" -d @- https://alerts.example.com/

# Log to file with timestamp
echo "$(date -Iseconds) $(s9-fdmap --json)" >> /var/log/fd_monitor.jsonl

# Pretty-print for debugging
s9-inspect 1234 --json | jq .
```


### Building Dashboards

The JSON output is designed to be dashboard-friendly:

```bash
# Prometheus-style metrics (with some jq magic)
s9-fdmap --json | jq -r '.summary[] | "fd_count{pid=\"\(.pid)\",name=\"\(.name)\"} \(.fd_count)"'
```

## See Also

- [Usage Guide](USAGE.md) — Detailed usage for all tools
- [Architecture](ARCHITECTURE.md) — How Substrata9 works internally
- [Examples](../examples/) — Ready-to-use scripts

*Part of Substrata9 — Linux Process Archaeology Toolkit*
