name: Feature Request
description: Suggest an idea for Substrata9
title: "[FEATURE] "
labels: ["enhancement"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for suggesting a feature! We appreciate your input.
  - type: input
    id: tool
    attributes:
      label: Related Tool
      description: Which tool would this feature affect? (or "new tool" for a new command)
      placeholder: s9-inspect, s9-tree, new tool
    validations:
      required: false
  - type: textarea
    id: problem
    attributes:
      label: Problem Statement
      description: What problem does this feature solve? What use case does it address?
      placeholder: I'm always frustrated when I need to...
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed Solution
      description: Describe the solution you'd like to see.
      placeholder: |
        Add a --json flag that outputs data in JSON format for scripting...
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives Considered
      description: Any alternative solutions or workarounds you've considered?
      placeholder: I currently work around this by piping to jq, but...
    validations:
      required: false
  - type: dropdown
    id: priority
    attributes:
      label: Priority
      description: How important is this feature to you?
      options:
        - Nice to have
        - Would significantly improve my workflow
        - Critical for my use case
    validations:
      required: true
