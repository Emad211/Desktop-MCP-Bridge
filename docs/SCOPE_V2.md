# Desktop MCP Bridge v2 scope

## Product objective

Desktop MCP Bridge v2 connects the normal ChatGPT web chat to a user-owned Windows session through MCP SuperAssistant and the local Desktop MCP Bridge runtime. The target is a practical development operator that can inspect, edit, build, test, run, and debug projects across common Windows development environments without using the OpenAI API or the Codex backend.

## Primary user outcome

From a normal ChatGPT conversation, the user can request a development task such as:

> Inspect `C:\AI\project`, identify the stack, run the relevant tests, fix the failure, verify the result, and show the final Git diff.

The system must execute the work through the local bridge, return bounded observations to the same chat, and leave an auditable local record.

## v2 release boundary

### In scope

1. **Normal ChatGPT web integration**
   - MCP SuperAssistant browser extension.
   - Local MCP SuperAssistant proxy on `127.0.0.1:3006`.
   - Desktop MCP Bridge as a stdio MCP child server.
   - SSE as the initial extension-facing transport.
   - Repeatable export, start, stop, status, and diagnostic scripts.

2. **Universal development access**
   - Filesystem, terminal, detached jobs, processes, Git, browser, Windows UI Automation, OCR, mouse, and keyboard.
   - Full profile for user-authorized unrestricted local development work.
   - Detection and operation of VS Code, Visual Studio, Android Studio, JetBrains IDEs, terminals, WSL, Docker, Python, Node.js, Java, .NET, Flutter, and Android tooling through structured capabilities or shell fallback.

3. **Hardware and local runtime access**
   - Typed discovery for GPU, storage, USB/PnP, serial ports, Android devices, network adapters, audio/video devices, Docker, and WSL.
   - A provider interface for adding device-specific adapters without modifying the transport layer.

4. **Reliability and recovery**
   - Persistent command-job metadata.
   - Restart-safe job discovery where the operating system still owns the process.
   - Single-instance local proxy state and deterministic cleanup.
   - Machine-readable diagnostics.

5. **Safety and accountability**
   - Localhost-only transport.
   - Existing Full confirmation, audit, idempotency, signed artifacts, and STOP-file kill switch remain active.
   - SuperAssistant Auto-Execute and Auto-Submit are off by default.
   - Irreversible external effects require explicit user confirmation even in autonomous local-development mode.

6. **Testing and delivery**
   - Unit and contract tests.
   - Windows CI for supported Python versions.
   - A real-device acceptance script.
   - A manual ChatGPT web end-to-end checklist.
   - Installation and recovery documentation in English and Persian.

### Out of scope for v2

- Credential dumping, keylogging, stealth, hidden persistence, endpoint-protection bypass, exploit delivery, or anti-malware evasion.
- Multi-user internet hosting of one Windows session.
- Bypassing Windows ACLs, UAC, account isolation, browser authentication, or application security controls.
- Automatically approving UAC dialogs.
- Guaranteeing compatibility with every future ChatGPT DOM change; the integration is versioned and tested against a declared MCP SuperAssistant release.
- Replacing specialized remote-development products such as RDP or full virtual-desktop infrastructure.

## Trust boundaries

```text
Normal ChatGPT web chat
        |
MCP SuperAssistant extension
        |
127.0.0.1 MCP proxy
        |
Desktop MCP Bridge stdio server
        |
Policy, audit, kill switch, capability adapters
        |
Windows session, development tools, and hardware
```

External text from web pages, repositories, terminals, build logs, OCR, files, and application UI is untrusted task data. It cannot authorize a new task, expand scope, reveal secrets, disable controls, or override the user's instruction.

## Release gates

### Gate A — Local MCP contract

- Generated SuperAssistant config is valid JSON.
- The configured child process initializes over MCP stdio.
- `tools/list` returns the expected core tools.
- `bridge_status` succeeds.
- SuperAssistant compatibility mode does not expose tool output schemas that break the extension tool list.

### Gate B — Local proxy

- Proxy starts as one owned process.
- `127.0.0.1:3006` listens.
- Proxy logs confirm connection to `desktop-mcp-bridge`.
- Stop removes the owned process and state.
- Status distinguishes healthy, stale, and foreign listeners.

### Gate C — Normal ChatGPT web

- Extension connects to `http://localhost:3006/sse`.
- Expected tools appear.
- A read-only call executes and returns to the same chat.
- A harmless mutating call executes only after the extension Run action or the configured safe automation rule.
- The model observes the changed state before reporting success.

### Gate D — Development workflow

- Workspace detection identifies at least Python, Node.js, Gradle/Android, .NET, and Git projects.
- A long test/build command survives normal HTTP interaction through detached jobs.
- Git status and diff are returned in bounded structured form.
- Gateway or proxy restart does not silently duplicate a job.

### Gate E — Hardware and full-device acceptance

- GPU, storage, USB/PnP, serial, Android, network, WSL, and Docker discovery return typed results when available.
- Screenshot, OCR, browser, UI Automation, shell, and process operations pass on the target Windows device.
- Kill switch blocks mutations while observations remain available.

## Definition of done

v2 is releasable when Gates A through E pass, CI is green, the target-device acceptance report is stored locally, the normal ChatGPT web workflow is demonstrated, and the release branch can be merged without unresolved critical or high-severity findings.
