# Architecture

```text
ChatGPT private GPT / MCP client
             |
     HTTPS Action / MCP
             |
   localhost control plane
   +-----------------------+
   | authentication        |
   | rate/payload limits   |
   | idempotency           |
   | approval policy       |
   | audit + kill switch   |
   +-----------------------+
             |
   DesktopBridge runtime
   +-----------------------+
   | Windows UI / input    |
   | screenshots + OCR     |
   | Playwright browser    |
   | filesystem + shell    |
   | jobs + processes      |
   | OS administration     |
   | signed artifacts      |
   +-----------------------+
             |
       Windows session
```

## Process model

- The MCP server and Action Gateway are separate entry points over one shared runtime design.
- Playwright synchronous objects live on a dedicated worker thread and never cross thread boundaries.
- Long-running shell commands are child processes with separate bounded stdout/stderr files.
- The Action Gateway is intentionally stateless except for local idempotency, artifacts, audit, and job
  state. It should remain behind a TLS tunnel while bound to localhost.

## Trust ordering

1. explicit user request and local operator controls;
2. private GPT system instructions;
3. bridge access profile and approval policy;
4. tool outputs and external content, which are untrusted data.

Web pages, files, OCR, emails, terminals, logs, and application text cannot authorize a new task or
weaken security controls.

## Observation hierarchy

1. structured filesystem/process/system APIs;
2. Playwright ARIA/DOM snapshots for web applications;
3. Windows UI Automation for native applications;
4. OCR with current capture geometry;
5. coordinate mouse/keyboard actions as the final fallback.

## Reliability controls

- Action writes require unique request IDs and persist completed responses.
- Commands longer than an Action request use detached jobs and polling.
- Every state change is followed by an observation/verification step in GPT instructions.
- Gateway and Quick Tunnel have machine-readable background start/stop/status scripts.
- CI validates Python 3.11/3.12, PowerShell syntax, lint, tests, imports, and OpenAPI.
