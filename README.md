# Desktop MCP Bridge

A local-first Windows control plane that turns an MCP client or a private Custom GPT into a
permissioned desktop agent. It can observe and operate applications, work with files, run terminal
commands, manage long-running jobs, inspect/control processes, automate Windows UI elements, and—in
explicit Full mode—perform operating-system administration.

> **This project is intentionally powerful.** Keep it bound to localhost, put authentication in
> front of every remote path, use the local kill switch, and never expose the gateway directly to the
> public internet.

## What changed in v0.2

- Three access profiles: `safe`, `developer`, and explicit `full`
- Private GPT Action Gateway with Bearer authentication
- Unrestricted shell and whole-account filesystem access in Full mode
- Administrator-aware registry, service, package, network, task, and power modules
- Windows UI Automation (`pywinauto`) in addition to mouse/keyboard control
- Clipboard and window management
- Binary file reads/writes plus copy, move, and recursive delete
- Detached command jobs with status, logs, polling, and cancellation
- Append-only, secret-redacted audit log
- Local STOP-file kill switch for all mutating operations
- OpenAPI schema and ready-to-paste private GPT instructions

## ChatGPT Pro: the practical connection path

There are two transports:

1. **MCP server** — best for MCP clients that permit write tools.
2. **GPT Action Gateway** — the practical route for a private Custom GPT on a ChatGPT Pro account.

At the time of this release, ChatGPT Pro custom MCP connections are limited to read/fetch tools; full
MCP write actions are available on eligible workspace plans. A private GPT Action can still invoke the
write gateway using an action-capable model. The bridge itself does not call the OpenAI API and does
not create API-token charges.

The Action route is text/JSON oriented and subject to the GPT Actions execution deadline. Commands
that may run for more than roughly 30 seconds should use `start_command_job`, followed by polling with
`get_command_job`.

## Capability matrix

| Capability | Safe | Developer | Full |
|---|:---:|:---:|:---:|
| Screenshots and mouse/keyboard | ✓ | ✓ | ✓ |
| Window listing/control | ✓ | ✓ | ✓ |
| Windows UI Automation tree/invoke | ✓ | ✓ | ✓ |
| Files under configured roots | ✓ | ✓ | ✓ |
| Files anywhere accessible to the Windows account | — | — | ✓ |
| Allowlisted shell commands | ✓ | ✓ | — |
| Unrestricted shell command line | — | — | ✓ |
| File deletion | — | ✓ | ✓ |
| Recursive deletion | — | — | ✓ |
| Process termination | — | ✓ | ✓ |
| Clipboard | — | ✓ | ✓ |
| Registry/services/packages/network/tasks/power | — | — | ✓ |
| Administrator-only OS changes | — | — | ✓, when locally elevated |

Full mode does not bypass Windows permissions. Run the bridge from an Administrator PowerShell when
the requested operation itself requires elevation.

## Requirements

- Windows 10 or Windows 11
- Python 3.11 or newer
- An interactive logged-in desktop session for visual/UI control
- For GPT Actions: a private Custom GPT and an HTTPS tunnel or reverse proxy that terminates TLS on
  port 443

## Install

```powershell

git clone https://github.com/Emad211/Desktop-MCP-Bridge.git
cd Desktop-MCP-Bridge
git switch feat/initial-desktop-bridge
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1
```

## Run the MCP server

### Safe profile

```powershell
.\scripts\run.ps1 -AllowedRoot "D:\AI-Workspace" -Profile safe
```

### Developer profile

```powershell
.\scripts\run.ps1 -AllowedRoot "D:\AI-Workspace" -Profile developer
```

### Full profile

Open PowerShell as Administrator when OS-wide administration is required:

```powershell
.\scripts\run-full-mcp.ps1 -Transport stdio -IUnderstand
```

Full mode requires both:

```text
DMB_ACCESS_PROFILE=full
DMB_FULL_ACCESS_CONFIRMATION=I UNDERSTAND THIS GRANTS FULL CONTROL
```

This deliberate two-part opt-in prevents a typo or copied environment file from silently granting
full control.

## Run the private GPT Action Gateway

Generate a random key:

```powershell
$ActionKey = .\scripts\new-action-key.ps1
```

Safe mode:

```powershell
.\scripts\run-actions.ps1 `
  -ApiKey $ActionKey `
  -AllowedRoot "D:\AI-Workspace" `
  -Profile safe
```

Full mode:

```powershell
.\scripts\run-actions.ps1 `
  -ApiKey $ActionKey `
  -FullAccess `
  -IUnderstand
```

The gateway listens only on:

```text
http://127.0.0.1:8766
```

For a temporary test URL, open a second PowerShell and run:

```powershell
.\scripts\run-quick-tunnel.ps1 -Port 8766 -InstallIfMissing
```

Copy the generated `https://...trycloudflare.com` URL into `gpt-actions.openapi.yaml`. Quick Tunnels
are temporary and intended for testing; use a named authenticated tunnel and stable hostname for
regular use. Place a secure HTTPS tunnel or authenticated reverse proxy in front of the bridge. Do
not bind the Python server directly to `0.0.0.0`, forward the port from your router, or publish the
bearer token.

### Configure a private GPT

1. Create a private GPT in ChatGPT.
2. Choose a model that supports GPT Actions rather than Pro mode.
3. Copy `gpt/INSTRUCTIONS.md` into the GPT instructions.
4. Add an Action and import `gpt-actions.openapi.yaml`.
5. Replace `https://YOUR_PUBLIC_HTTPS_HOST` with the HTTPS tunnel hostname.
6. Configure API-key authentication using Bearer format and paste `$ActionKey`.
7. Keep the GPT private.
8. Test `healthCheck`, then `observeComputer` with operation `status`.

All state-changing requests use the consequential `controlComputer` action, allowing ChatGPT's
confirmation flow to remain visible to the user.

## Available operations

### Observation

- `status`
- `system_info`
- `observe_desktop` — MCP image output
- `list_directory`
- `read_text_file`
- `read_binary_file`
- `get_command_job`
- `list_command_jobs`
- `list_processes`
- `clipboard_read`
- `list_windows`
- `uia_tree`
- `registry_get`
- `audit_tail`

### Control

- `desktop_step`
- `write_text_file`
- `write_binary_file`
- `copy_path`
- `move_path`
- `delete_path`
- `run_command`
- `start_command_job`
- `cancel_command_job`
- `stop_process`
- `clipboard_write`
- `window_control`
- `uia_invoke`
- `registry_set`
- `registry_delete`
- `service_control`
- `package_manage`
- `network_admin`
- `scheduled_task_control`
- `power_control`

## Long-running command pattern

Start work without blocking the Action request:

```json
{
  "operation": "start_command_job",
  "arguments": {
    "command": "gradlew.bat build",
    "cwd": "D:/Projects/MyApp"
  }
}
```

Poll it:

```json
{
  "operation": "get_command_job",
  "arguments": {
    "job_id": "returned-job-id",
    "tail_bytes": 50000
  }
}
```

Cancel if needed:

```json
{
  "operation": "cancel_command_job",
  "arguments": {
    "job_id": "returned-job-id",
    "force": true
  }
}
```

## UI Automation before coordinate clicks

For supported Windows applications, prefer:

```text
list_windows → uia_tree → uia_invoke → uia_tree
```

This uses accessible UI elements and is usually more reliable than fixed screen coordinates. Use
`desktop_step` when an application does not expose usable automation elements.

## Kill switch

Stop all mutating operations locally even if the remote session remains active:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

Inspect or re-enable:

```powershell
.\scripts\kill-switch.ps1 -Mode Status
.\scripts\kill-switch.ps1 -Mode Disable
```

Read-only status and audit inspection remain available so the operator can diagnose the situation.

## Audit trail

Every operation records:

- UTC timestamp
- source (`mcp`, `gpt-action`, or local)
- operation name
- redacted arguments
- success/failure
- bounded result or error

The default JSONL file is in the Windows per-user application state directory. Its exact path is
returned by `status`. Common password/token/API-key fields are redacted before writing.

## Security boundaries

- Full mode removes project root and command allowlist restrictions; it does **not** defeat Windows
  ACLs, UAC, endpoint protection, or account separation.
- No credential dumping, keylogging, anti-malware bypass, hidden persistence, or stealth facilities
  are implemented.
- `pyautogui` fail-safe remains enabled: moving the pointer rapidly to the upper-left corner can
  interrupt visual automation.
- The bearer key is authentication, not transport encryption. HTTPS is still mandatory remotely.
- A private GPT endpoint controls the Windows account that runs it. Treat the endpoint and key like
  a remote-administration credential.
- Prefer a separate Windows account or VM for highly autonomous sessions.

See `SECURITY.md` and `docs/THREAT_MODEL.md`.

## Local MCP client example

```json
{
  "mcpServers": {
    "desktop-bridge": {
      "command": "C:\\path\\Desktop-MCP-Bridge\\.venv\\Scripts\\desktop-mcp-bridge.exe",
      "args": ["mcp"],
      "env": {
        "DMB_TRANSPORT": "stdio",
        "DMB_ACCESS_PROFILE": "developer",
        "DMB_ALLOWED_ROOTS": "[\"D:/AI-Workspace\"]"
      }
    }
  }
}
```

## Testing

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\ruff.exe check .
```

CI runs on Windows with Python 3.11 and 3.12.

## Roadmap

- Signed Windows installer and tray UI
- One-click named Cloudflare Tunnel bootstrap
- Local approval dashboard and per-operation grants
- Persisted/recoverable job metadata after bridge restart
- Named-pipe local control channel
- Multi-monitor visual coordinate mapping
- Browser automation adapter using Playwright/CDP
- File upload/download handling for the GPT Action route

## License

MIT
