name: Bug Report
description: Create a report to help us improve Substrata9
title: "[BUG] "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to fill out this bug report!
  - type: input
    id: tool
    attributes:
      label: Affected Tool
      description: Which tool is causing the issue? (e.g., s9-inspect, s9-tree)
      placeholder: s9-inspect
    validations:
      required: true
  - type: textarea
    id: description
    attributes:
      label: Describe the Bug
      description: A clear and concise description of what the bug is.
      placeholder: When I run s9-inspect on a zombie process...
    validations:
      required: true
  - type: textarea
    id: reproduction
    attributes:
      label: Reproduction Steps
      description: Steps to reproduce the behavior.
      placeholder: |
        1. Create a zombie process
        2. Run './bin/s9-inspect <pid>'
        3. See error...
    validations:
      required: true
  - type: input
    id: environment
    attributes:
      label: Environment
      description: OS version, Bash version, Kernel version
      placeholder: Ubuntu 22.04, Bash 5.1, Kernel 5.15
    validations:
      required: true
  - type: textarea
    id: logs
    attributes:
      label: Output / Logs
      description: Paste the output or error message here.
      render: shell
