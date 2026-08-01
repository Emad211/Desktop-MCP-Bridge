---
name: add-or-update-documentation
description: Workflow command scaffold for add-or-update-documentation in Desktop-MCP-Bridge.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /add-or-update-documentation

Use this workflow when working on **add-or-update-documentation** in `Desktop-MCP-Bridge`.

## Goal

Adds or updates documentation files to define scope, plans, strategies, instructions, or runbooks.

## Common Files

- `docs/*.md`
- `docs/ADR/*.md`
- `gpt/*.md`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Create or update a markdown file in docs/ or gpt/ or docs/ADR/ directories
- Commit with a 'docs:' prefix in the message

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.