```markdown
# Desktop-MCP-Bridge Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches the core development patterns and workflows used in the Desktop-MCP-Bridge Python codebase. You'll learn the project's coding conventions, commit standards, documentation and scripting workflows, and how to contribute effectively using standardized commands.

## Coding Conventions

### File Naming
- Use **snake_case** for all Python files and scripts.
  - Example: `mcp_bridge.py`, `proxy_manager.py`

### Import Style
- Use **relative imports** within the package.
  - Example:
    ```python
    from .utils import parse_config
    ```

### Export Style
- Use **named exports** (explicitly define what is exported from a module).
  - Example:
    ```python
    __all__ = ['MCPBridge', 'ProxyManager']
    ```

### Commit Messages
- Follow **conventional commit** patterns.
  - Prefixes: `docs:`, `feat:`, `test:`
  - Example:
    ```
    feat: add proxy manager for SuperAssistant integration
    docs: update runbook for new deployment process
    test: add integration test for bridge connection
    ```

## Workflows

### Add or Update Documentation
**Trigger:** When you need to document new features, strategies, or operational instructions.  
**Command:** `/add-docs`

1. Create or update a markdown file in one of these directories:
    - `docs/`
    - `docs/ADR/`
    - `gpt/`
2. Write clear documentation defining scope, plans, strategies, instructions, or runbooks.
3. Commit your changes with a `docs:` prefix in the message.
    - Example:
      ```
      docs: add ADR for proxy management strategy
      ```
4. Push your changes and open a pull request if required.

### Add or Update SuperAssistant PowerShell Scripts
**Trigger:** When you want to add or improve automation for SuperAssistant proxy operations or integration tests.  
**Command:** `/add-superassistant-script`

1. Create or update a PowerShell script in the `scripts/` directory with a name matching `*superassistant*.ps1`.
    - Example: `scripts/setup_superassistant_proxy.ps1`
2. Implement or update automation logic as needed.
3. Commit your changes with a `feat:` or `test:` prefix in the message.
    - Example:
      ```
      feat: add SuperAssistant proxy setup script
      test: update SuperAssistant integration test script
      ```
4. Push your changes and open a pull request if required.

## Testing Patterns

- Test files follow the pattern: `*.test.*`
    - Example: `proxy_manager.test.py`
- The testing framework is not explicitly specified; check existing test files for conventions.
- Place test files alongside the modules they test or in a dedicated test directory if present.

## Commands

| Command                     | Purpose                                                        |
|-----------------------------|----------------------------------------------------------------|
| /add-docs                   | Start or update documentation in `docs/`, `docs/ADR/`, or `gpt/` |
| /add-superassistant-script  | Add or update SuperAssistant PowerShell scripts in `scripts/`   |
```