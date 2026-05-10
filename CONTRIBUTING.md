# Contributing to Substrata9

Contributions to Substrata9 are welcome! This document outlines the process for contributing code, documentation, or reporting issues.

---

## Development Workflow

### Prerequisites
Ensure your development environment meets the following requirements:
*   Bash 4.0+
*   `shellcheck` (for linting)
*   Standard Linux utilities (`awk`, `sed`, `grep`, `bc`)

### Getting Started

1.  **Fork and Clone:**
    Fork the repository on GitHub and clone your fork locally.
    ```bash
    git clone https://github.com/iamrahulreddy/Substrata9.git
    cd Substrata9
    ```

2.  **Create a Branch:**
    Create a feature branch for your changes.
    ```bash
    git checkout -b feature/description-of-change
    ```

3.  **Implement Changes:**
    Make your code or documentation changes. Ensure all scripts are executable.

4.  **Verify:**
    Run the test suite and linter to ensure no regressions were introduced.
    ```bash
    make test
    make lint
    ```

5.  **Commit and Push:**
    Commit your changes with a clear, descriptive message.
    ```bash
    git commit -m "feat: add support for custom output formats"
    git push origin feature/description-of-change
    ```

6.  **Submit Pull Request:**
    Open a Pull Request against the main repository.

---

## Coding Standards

### Shell Scripting Guidelines
*   **Shebang:** Use `#!/usr/bin/env bash`.
*   **Safety:** Always use `set -euo pipefail` (or `set -uo pipefail` where race conditions are expected).
*   **Indentation:** Use 4 spaces. No tabs.
*   **Naming Conventions:**
    *   Variables: `lowercase_with_underscores`
    *   Constants/Environment Variables: `UPPERCASE_WITH_UNDERSCORES`
    *   Functions: `lowercase_with_underscores`
*   **Dependencies:** Source the common library (`lib/s9-common.sh`) for shared functionality.

### Common Library Usage
Utilize the provided helper functions in `lib/s9-common.sh` for consistency:

*   **Output:** `s9_info`, `s9_warn`, `s9_die`
*   **Formatting:** `s9_human_bytes`, `s9_human_duration`
*   **Process Retrieval:** `s9_resolve_pid`, `s9_get_rss`

---

## Testing

All contributions must pass the automated test suite.

*   **Run all tests:** `make test` (wraps `tests/run_tests.sh`)
*   **Run specific tool test:** `./tests/test_tools.sh`
*   **Linting:** `make lint`

If adding a new feature, please include a corresponding test case in the `tests/` directory.

---

## Issue Reporting

When reporting issues, please provide:
1.  The specific command run.
2.  The output (including error messages).
3.  System information (OS, Kernel version, Bash version).

---

Thank you for contributing to the project.
