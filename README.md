# Substrata9

[![CI Status](https://github.com/iamrahulreddy/Substrata9/actions/workflows/ci.yml/badge.svg)](https://github.com/iamrahulreddy/Substrata9/actions/workflows/ci.yml)
[![Linux](https://img.shields.io/badge/Linux-Kernel_4.15+-FCC624?logo=linux&logoColor=black)](https://kernel.org)
[![Bash](https://img.shields.io/badge/Bash_4.0+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Dependency-light, container-aware process diagnostic toolkit for Linux.**

Substrata9 is a pure-Bash diagnostic toolkit designed for low-friction system inspection. It interfaces directly with the Linux `/proc` filesystem and relies only on Bash plus standard Linux userland utilities; there are no compiled components, daemons, or service installation requirements. A single archive extraction is sufficient for deployment while still providing granular insights into memory maps, signal handlers, GPU allocations, and process hierarchies.

## Nomenclature

The name **Substrata9** reflects the architectural intent of the software:

* **Substrata** (Latin): Derived from *substratum*, meaning the fundamental underlying layer. While standard tools monitor surface-level metrics (e.g., CPU load), this toolkit inspects the *substrata* — the memory segments and kernel limits that constitute the foundation of a process.
* **9**: A reference to **Section 9 of the Unix Manual**. While standard Linux manual pages typically conclude at Section 8 (System Administration), Section 9 was historically reserved for **Kernel Routines**. This number signifies the boundary where user space interacts with kernel space — the specific operational domain of this toolkit.

## Demos

### Process Inspection (`s9-inspect`)
Detailed analysis of a single process, displaying memory segmentation, resource limits, and signal dispositions.

![s9-inspect demo](GIFS/01-inspect.gif)

### File Descriptor Analysis (`s9-fdmap`)
System-wide visualization of open file descriptors to assist in identifying resource leaks.

![s9-fdmap demo](GIFS/05-fdmap.gif)

> **[View detailed documentation and usage examples](docs/USAGE.md)**

## Quick Start

Substrata9 is script-based and requires no installation. It runs directly from the cloned repository.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/iamrahulreddy/Substrata9.git
    cd Substrata9
    ```

2.  **Set execution permissions:**
    ```bash
    chmod +x bin/*
    ```

3.  **Execute the inspection tool:**
    ```bash
    ./bin/s9-inspect <PID>
    ```

### System-Wide Installation
To install the executables to the system path:
```bash
sudo make install
```

## Toolkit Components

| Tool | Description |
|------|-------------|
| **s9-inspect** | **Diagnostic:** Provides a comprehensive view of a single process (Memory, FDs, Limits, Signals). |
| **s9-tree** | **Hierarchy:** Visualizes the process tree with context regarding resource usage for parent and child processes. |
| **s9-fdmap** | **Analysis:** Audits system-wide file descriptors to identify usage patterns or leaks. |
| **s9-snapshot** | **State Capture:** Captures the state of a process at a specific timestamp for future comparison. |
| **s9-compare** | **Diff:** Performs a side-by-side comparison of two distinct processes or snapshots. |
| **s9-anomaly** | **Heuristics:** Scans the system for zombie processes, orphans, and abnormal resource consumption. |
| **s9-gpu** | **Hardware:** Maps NVIDIA GPU memory allocations to specific Linux processes using `nvidia-smi`. |

All tools support the `-j` / `--json` flag to output data in structured JSON format, as well as the `-e` / `--export-json` flag to automatically save the JSON output to a timestamped file for external logging or telemetry integration.

## Architecture

Substrata9 functions as a transparency layer for the Linux kernel, bypassing standard utilities like `top` or `ps`.

1.  **Data Acquisition:** The scripts read raw data streams directly from `/proc/[pid]/maps`, `/proc/[pid]/fd`, and `/proc/[pid]/status`.
2.  **Parsing:** The tool utilizes native Bash arithmetic and `awk` to interpret hex addresses, bitmasks, and kernel flags.
3.  **Presentation:** Data is formatted into human-readable ASCII tables or JSON.

This direct approach ensures that the data presented is an accurate, unadulterated representation of the kernel's current state.

> [!NOTE]
> **Recursion & Stack Depth**  
> `s9-tree` uses recursive function calls to traverse the process hierarchy.  
> While this approach is elegant and readable, it is theoretically limited by the shell’s stack size.  
>  
> In practice, typical Linux process trees rarely exceed a depth of ~10, keeping execution well within safe bounds.  
> Only artificially constructed, extremely deep process chains may risk stack exhaustion.

## Validated Platforms

Substrata9 has been tested across the following GPU-accelerated environments as of 2026-05-20. Each run completed 18/18 stages with 0 failures and 0 red flags; optional-tool skips are reported separately by the test harness.

| Environment | GPU | RAM | Test Result |
|-------------|-----|-----|-------------|
| Google Colab | Tesla T4 16 GB | 12 GB | 18/18 stages, 0 red flags |
| Lightning AI | A100 40 GB | 30-core CPU | 18/18 stages, 0 red flags |
| Modal (Firecracker) | H100 80 GB | Containerized | 18/18 stages, 0 red flags |

## Limitations

Substrata9 is built for interactive diagnostics and ad-hoc debugging, not continuous production monitoring. The following constraints should be understood before adoption:

* **Not a production monitoring agent.** Each invocation is a one-shot scan with no daemon mode, no caching, and no event-driven architecture. For high-frequency, continuous monitoring, use purpose-built tools like Prometheus node_exporter, Datadog, or eBPF-based solutions.
* **Shell performance ceiling.** Pure Bash is inherently slower than compiled alternatives. Single-process inspection runs in ~12 ms and full anomaly scans in ~300 ms at idle, but these numbers increase under heavy system load. On systems with thousands of processes, tools like `s9-tree` and `s9-fdmap` will be noticeably slower than their C/Go equivalents.
* **GPU PID attribution is best-effort in containers.** In certain container runtimes (Modal Firecracker, some Kubernetes configurations), `nvidia-smi` cannot map GPU memory to the local PID namespace. Substrata9 detects this and reports aggregate GPU memory, but per-process GPU attribution is unavailable in those environments.
* **Root access required for full visibility.** Many `/proc` files (I/O stats, FD targets for other users' processes, memory maps) are restricted by the kernel. Running without root produces partial output — this is a Linux security feature, not a bug.
* **Signal masks truncated to 32 bits.** `/proc/[pid]/status` exposes 64-bit signal masks, but Substrata9 decodes only the lower 32 bits (standard POSIX signals 1–31). Real-time signals (32–64) are not decoded.
* **Linux only.** Substrata9 depends on the Linux `/proc` filesystem. It does not support macOS, FreeBSD, or Windows natively. WSL 2 is supported but limited to the Linux subsystem.
* **Process race conditions.** Processes can exit between directory listing and file reading. All tools handle this gracefully (skipping vanished processes), but scan results represent a best-effort point-in-time snapshot, not an atomic view.

## Requirements

* **Operating System:** Linux (Kernel 4.15 or newer recommended).
* **Shell:** Bash 4.0 or newer.
* **Dependencies:** `awk`, `sed`, `grep`, `pgrep`, `readlink`, `getconf`, `mktemp`, `sort`, `head`, `tail`, `tr`, `wc`, `du`; `bc` or the bundled lightweight fallback in `bin/bc`.
* **Optional:** `timeout`, `realpath`, `getent`, `jq` (for external JSON filtering — not used by the tools internally), `nvidia-smi` (for GPU visibility).

> **Note on Windows (WSL):** Substrata9 is compatible with WSL 2; however, it is limited to inspecting the Linux subsystem. It cannot access or inspect Windows host processes running outside the WSL environment.

## Contributing

Contributions to the codebase are welcome. Please adhere to the following workflow:

1.  Fork the repository.
2.  Create a feature branch.
3.  Execute the test suite (`make test`) to ensure functionality.
4.  Submit a Pull Request.

Refer to [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

This software is distributed under the MIT License. Refer to the [LICENSE](LICENSE) file for full text.

**Author:** Muskula Rahul — [@iamrahulreddy](https://github.com/iamrahulreddy)
