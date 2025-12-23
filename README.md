# Substrata9

[![CI Status](https://github.com/iamrahulreddy/Substrata9/actions/workflows/ci.yml/badge.svg)](https://github.com/iamrahulreddy/Substrata9/actions/workflows/ci.yml)
[![Linux](https://img.shields.io/badge/Linux-Kernel_4.15+-FCC624?logo=linux&logoColor=black)](https://kernel.org)
[![Bash](https://img.shields.io/badge/Bash_4.0+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Deep process visibility for Linux systems.**

Substrata9 is a pure Bash diagnostic utility designed for low-friction system inspection. Unlike conventional monitoring agents that require heavy binaries or abstraction layers, Substrata9 interacts directly with the Linux /proc filesystem. This approach ensures a negligible system footprint, zero compilation requirements, and absolute portability while providing granular insights into memory maps, signal handlers, and process hierarchies.

## Nomenclature

I selected the name **Substrata9** to reflect the architectural intent of the software:

* **Substrata** (Latin): Derived from *substratum*, meaning the fundamental underlying layer. While standard tools monitor surface-level metrics (e.g., CPU load), I designed this tool to inspect the *substrata*—the memory segments and kernel limits that constitute the foundation of a process.
* **9**: A reference to **Section 9 of the Unix Manual**. While standard Linux manual pages typically conclude at Section 8 (System Administration), Section 9 was historically reserved for **Kernel Routines**. This number signifies the boundary where user space interacts with kernel space—the specific operational domain of this toolkit.

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

All tools support the `--json` flag to output data in structured JSON format for integration with external logging or monitoring systems.

## Architecture

I designed Substrata9 to function as a transparency layer for the Linux kernel, bypassing standard utilities like `top` or `ps`.

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

## Requirements

* **Operating System:** Linux (Kernel 4.15 or newer recommended).
* **Shell:** Bash 4.0 or newer.
* **Dependencies:** `awk`, `sed`, `grep`, `bc`.
* **Optional:** `jq` (Required only for JSON output formatting).

> **Note on Windows (WSL):** Substrata9 is compatible with WSL 2; however, it is limited to inspecting the Linux subsystem. It cannot access or inspect Windows host processes running outside the WSL environment.

## Contributing

I welcome contributions to the codebase. Please adhere to the following workflow:

1.  Fork the repository.
2.  Create a feature branch.
3.  Execute the test suite (`make test`) to ensure functionality.
4.  Submit a Pull Request.

Refer to [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

This software is distributed under the MIT License. Refer to the [LICENSE](LICENSE) file for full text.

**Author:** Muskula Rahul — [@iamrahulreddy](https://github.com/iamrahulreddy)
