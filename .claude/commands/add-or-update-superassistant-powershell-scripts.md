---
name: add-or-update-superassistant-powershell-scripts
description: Workflow command scaffold for add-or-update-superassistant-powershell-scripts in Desktop-MCP-Bridge.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /add-or-update-superassistant-powershell-scripts

Use this workflow when working on **add-or-update-superassistant-powershell-scripts** in `Desktop-MCP-Bridge`.

## Goal

Adds or updates PowerShell scripts related to SuperAssistant proxy management or integration testing.

## Common Files

- `scripts/*superassistant*.ps1`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Create or update a PowerShell script in scripts/ with a name matching *superassistant*.ps1
- Commit with a 'feat:' or 'test:' prefix in the message

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.