# Desktop MCP Bridge v2 delivery plan

## Delivery principle

The project follows a test-first critical path. Work that does not contribute to the next executable acceptance gate is deferred. The first usable milestone is not the complete hardware SDK; it is a verified round trip from normal ChatGPT web chat to a harmless Windows action and back.

## Current baseline

Base branch: `feat/initial-desktop-bridge`

Continuation branch: `feat/chat-superassistant-universal-runtime`

The baseline already contains the Windows runtime, MCP server, GPT Action gateway, browser and OCR support, UI Automation, shell and job control, Full/Safe/Developer profiles, audit, idempotency, DPAPI key handling, network resilience, diagnostics, and Windows CI.

## Critical path

```text
P0 freeze scope
  -> P1 SuperAssistant compatibility and config
  -> P2 local proxy lifecycle
  -> P3 MCP/proxy automated preflight
  -> P4 normal ChatGPT web acceptance
  -> P5 structured development capabilities
  -> P6 persistent jobs
  -> P7 hardware adapters
  -> P8 full Windows acceptance and release
```

## P0 — Scope and engineering controls

### Deliverables

- `docs/SCOPE_V2.md`
- `docs/DELIVERY_PLAN_V2.md`
- `docs/TEST_STRATEGY_V2.md`
- `docs/ADR/0001-superassistant-local-transport.md`

### Exit criteria

- Scope has explicit in/out boundaries.
- Every phase has measurable acceptance criteria.
- The first testable milestone is isolated from later IDE and hardware enhancements.

## P1 — SuperAssistant MCP compatibility

### Deliverables

- Compatibility entry point that suppresses MCP structured output schemas for the SuperAssistant path while preserving the standard MCP entry point.
- Config exporter that generates an absolute Windows stdio server configuration.
- Dedicated SuperAssistant operating instructions.
- Unit and contract tests for compatibility behavior.

### Exit criteria

- Generated config starts the correct Python executable and module.
- MCP initialize and `tools/list` succeed through stdio.
- Core tools include `bridge_status`, `run_command`, `start_command_job`, `browser_snapshot`, and `uia_tree`.
- SuperAssistant-facing tools omit incompatible output schemas.

## P2 — Local proxy lifecycle

### Deliverables

- `scripts/start-superassistant-proxy.ps1`
- `scripts/stop-superassistant-proxy.ps1`
- `scripts/status-superassistant-proxy.ps1`
- Process ownership state under `%LOCALAPPDATA%\DesktopMCPBridge`.
- Bounded stdout/stderr logs.

### Exit criteria

- Start is idempotent.
- Restart replaces only the owned proxy process.
- A foreign process on port 3006 is detected and never killed automatically.
- Status reports PID, endpoint, transport, config, listener ownership, and log tails.
- Stop leaves no owned listener.

## P3 — Automated preflight

### Deliverables

- MCP stdio probe.
- SuperAssistant integration preflight script.
- CI checks for config contract and compatibility mode.

### Exit criteria

- One command validates config, MCP initialize, tools list, status tool call, proxy startup, child-server connection, and local listener.
- Failures identify the exact layer: Python runtime, MCP child, proxy, port ownership, or extension handoff.

## P4 — Normal ChatGPT web acceptance

### Deliverables

- Extension installation guide.
- Exact connection settings for SSE.
- Manual acceptance checklist.
- Version record for the tested extension and proxy.

### Acceptance sequence

1. Start proxy.
2. Reload the extension.
3. Connect to `http://localhost:3006/sse`.
4. Confirm expected tool count.
5. Insert the provided MCP operating instructions.
6. Call `bridge_status`.
7. Read a harmless test file.
8. Create a harmless file in an isolated acceptance directory.
9. Read it back and verify contents.
10. Enable the kill switch and prove the write is rejected.
11. Disable the kill switch and clean the test directory.

### Exit criteria

- Tool calls render in normal ChatGPT web.
- Tool results are reinserted into the same conversation.
- Read and harmless write operations pass.
- No OpenAI API key or Codex backend is used.

## P5 — Structured development capabilities

### Initial tool groups

- `workspace_discover`
- `workspace_inspect`
- `environment_detect`
- `git_status`
- `git_diff`
- `test_discover`
- `test_run`
- `build_discover`
- `build_run`
- `ide_discover`
- `ide_open_project`

### Design rule

Structured tools are preferred for common workflows. Existing unrestricted Full shell remains the universal fallback for environments not yet modeled.

### Exit criteria

- Python, Node.js, Gradle/Android, .NET, and generic Git workspaces are detected.
- Test and build commands are selected from project evidence, not guessed.
- Results are bounded and include command, working directory, exit code, and output tail.

## P6 — Persistent command jobs

### Deliverables

- Durable job metadata.
- Process start-time and command fingerprint.
- Restart-time reconciliation.
- Orphan and stale-state handling.

### Exit criteria

- Completed jobs remain queryable after restart.
- Running jobs are reattached only when PID and process identity match.
- Stale PID reuse is rejected.
- Duplicate jobs are not started after a response timeout.

## P7 — Hardware capability adapters

### Initial providers

- GPU/NVIDIA
- disks and volumes
- USB and PnP
- serial ports
- Android/ADB
- network adapters
- WSL
- Docker
- audio and camera devices

### Exit criteria

- Each provider has availability detection and typed output.
- Missing vendor tools produce `unavailable`, not an unhandled failure.
- Device-specific write operations remain separate from read-only discovery.

## P8 — Full Windows acceptance and release

### Deliverables

- Real-device acceptance runner.
- Acceptance report JSON.
- Upgrade and recovery documentation.
- Release notes.
- Merge-ready PR.

### Exit criteria

- CI is green.
- Normal ChatGPT web acceptance passes.
- Existing v1.2 gateway identity checks still pass.
- Browser, OCR, UI Automation, files, jobs, process control, development workflow, and hardware discovery pass on the target device.
- Critical and high-severity defects are closed.

## Deferred backlog

The following work must not block the first normal-Chat test:

- polished desktop GUI;
- marketplace packaging;
- multi-machine coordination;
- remote internet MCP hosting;
- advanced IDE protocol integrations;
- vendor-specific hardware write controls;
- automatic browser-extension installation.

## Immediate execution order

1. Commit the v2 engineering documents.
2. Implement SuperAssistant compatibility mode.
3. Implement config export and proxy lifecycle scripts.
4. Add stdio and preflight probes.
5. Run CI.
6. Perform the normal ChatGPT web acceptance on the target Windows device.
7. Only after Gate C passes, begin structured IDE and hardware capabilities.
