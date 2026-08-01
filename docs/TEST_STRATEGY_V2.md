# Desktop MCP Bridge v2 test strategy

## Objectives

The test strategy must answer five separate questions:

1. Is the Python runtime correct?
2. Does the MCP contract work independently of the browser extension?
3. Does the local SuperAssistant proxy correctly expose the bridge?
4. Does an MCP client complete a real initialize/list/call round trip through the browser-facing SSE endpoint?
5. Can normal ChatGPT web discover, execute, and consume the tools on the target Windows device?

A green unit suite is necessary but not sufficient. Windows desktop, UI Automation, browser, OCR, UAC, proxy, SSE transport, and extension behavior require integration or real-device acceptance.

## Test layers

## Layer 1 — Static validation

Runs on every push and pull request.

- Python compileall.
- Ruff.
- PowerShell parser validation for every script.
- OpenAPI and version consistency.
- JSON template parsing.
- No secret material in committed integration templates.

## Layer 2 — Unit tests

Runs on Windows for Python 3.11, 3.12, and 3.13.

Required areas:

- SuperAssistant compatibility transformation.
- Config export normalization.
- path and command policy.
- idempotency.
- audit redaction.
- artifact signing.
- job persistence and reconciliation.
- development project detection.
- hardware provider parsing.

Coverage is tracked by subsystem. The project must not use total coverage alone to hide low coverage in consequential Windows tools.

## Layer 3 — MCP child contract tests

The child server is launched over stdio exactly as the generated SuperAssistant config launches it.

Required sequence:

1. `initialize`.
2. `notifications/initialized`.
3. `tools/list`.
4. Assert expected tools.
5. Assert SuperAssistant-facing tools omit `outputSchema`.
6. `tools/call` for `bridge_status`.
7. Clean shutdown.

Failures must include the child stderr tail and the last valid JSON-RPC message.

## Layer 4 — Proxy lifecycle tests

The pinned proxy runtime is started on an unused localhost port by launching its JavaScript entry point directly with hidden `node.exe`.

Required assertions:

- one owned process;
- listener PID is owned by the recorded process tree;
- launcher and listener are `node` processes;
- launch method is `direct-node-hidden`;
- proxy log reports connection to `desktop-mcp-bridge`;
- no `Failed to connect` entry for the bridge;
- expected endpoint is reported;
- restart replaces the owned process;
- foreign listener is not terminated;
- stop removes only the owned process and leaves no owned listener.

The release path uses SSE first because it is the most established extension-facing mode. Streamable HTTP remains an experimental secondary path until the extension's open tool-list and response issues are verified closed.

## Layer 5 — Browser-facing SSE contract

This layer verifies the exact network path used by MCP SuperAssistant without depending on the ChatGPT DOM.

The test client connects to `http://localhost:<port>/sse` using the MCP SDK, then performs:

1. SSE connection and message endpoint negotiation.
2. MCP `initialize`.
3. `tools/list` through the proxy.
4. Assert `bridge_status`, `read_text_file`, `write_text_file`, and `run_command` are present.
5. `tools/call` for `bridge_status`.
6. Assert the call does not return `isError=true`.
7. Close the client while leaving the managed proxy healthy.

This layer distinguishes three otherwise-confusable failures:

- child MCP failure;
- proxy aggregation/listener failure;
- browser-facing SSE protocol failure.

The probe is implemented by `scripts/probe_superassistant_sse.py` and runs both in CI and the one-command target-device preflight.

## Layer 6 — Target Windows runtime tests

Runs on the user's actual interactive Windows session.

### Observation tests

- status and system information;
- screenshot;
- English and Persian OCR;
- window listing;
- UI Automation tree;
- browser status and snapshot;
- files and processes;
- audit tail;
- development environment discovery;
- hardware discovery.

### Mutation tests

All mutation tests use an isolated acceptance directory and disposable processes.

- create, update, copy, move, and delete test files;
- start, poll, complete, and cancel command jobs;
- clipboard write/read restoration;
- browser navigation and semantic interaction;
- harmless UI Automation action;
- kill-switch rejection;
- job and proxy recovery after restart.

No acceptance test changes system services, registry, network configuration, scheduled tasks, or power state unless that test is explicitly selected and confirmed by the operator.

## Layer 7 — Normal ChatGPT web acceptance

Manual because it depends on the extension, ChatGPT DOM, account state, and browser session.

### Preconditions

- normal ChatGPT web chat is available;
- MCP SuperAssistant extension is installed and enabled;
- only one relevant AI-chat tab is open during initial diagnosis;
- stdio, proxy lifecycle, and SSE contract probes are green;
- proxy status is healthy;
- Auto-Execute and Auto-Submit are disabled;
- an isolated acceptance directory exists.

### Required cases

| Case | Expected result |
|---|---|
| Connect extension | Status changes to Connected |
| Refresh tools | Core tools are visible |
| Insert instructions | Model uses the required tool-call format |
| `bridge_status` | Read-only result returns to the same chat |
| Read acceptance file | Exact content is returned |
| Create acceptance file | Tool card requires manual Run by default |
| Verify write | A read confirms the new content |
| Kill switch on | Mutation fails; observation still succeeds |
| Kill switch off | Mutation succeeds again |
| Long command | One job is started and polled; no duplicate |

### Evidence

The local acceptance report records:

- bridge Git SHA;
- Python and Windows versions;
- extension version;
- proxy package and version;
- proxy transport and endpoint;
- stdio and SSE probe results;
- expected and observed tool counts;
- passed/failed cases;
- redacted log locations;
- screenshots only when they contain no sensitive data.

## Failure classification

- **L0 Python/runtime:** import, dependency, syntax, or process startup failure.
- **L1 MCP child:** initialize, tools list, or direct child tool-call failure.
- **L2 proxy lifecycle:** child aggregation, listener, process ownership, start, restart, or stop failure.
- **L3 SSE transport:** browser-facing connection, message negotiation, proxied tools list, or proxied tool-call failure.
- **L4 extension:** connection, tool discovery, rendering, Run, or result insertion failure.
- **L5 model protocol:** malformed tool-call output or failure to follow inserted instructions.
- **L6 desktop capability:** Windows, browser, OCR, UIA, shell, development, or hardware failure.

Every diagnostic command must identify one of these layers instead of returning a generic "connection failed" message.

## Release quality thresholds

- all CI matrices pass;
- no PowerShell parser errors;
- all MCP child contract tests pass;
- all proxy lifecycle tests pass;
- the browser-facing SSE contract passes in CI and on the target device;
- all normal ChatGPT web acceptance cases pass;
- no unresolved critical or high-severity security issue;
- no known duplicate-execution defect;
- no secret appears in Git, logs, reports, or chat output;
- existing v1.2 functionality remains operational.
