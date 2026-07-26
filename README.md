# Desktop MCP Bridge

Desktop MCP Bridge is a local-first Windows control plane that turns an MCP client or a private
Custom GPT into a permissioned desktop operator. It combines native Windows UI automation, screen
capture and OCR, a managed Playwright browser, filesystem and terminal tools, long-running jobs,
process/system administration, short-lived screenshot artifacts, audit logging, and a local kill
switch.

> This project is intentionally powerful. Keep the Python services bound to localhost, expose them
> only through an authenticated HTTPS tunnel, keep the GPT private, and protect the bearer key like a
> remote-administration credential.

## v1.0 highlights

- Safe, Developer, and explicit Full access profiles
- Private GPT Action Gateway with Bearer authentication
- Idempotent write requests to prevent duplicate actions after retries
- Guarded or Autonomous approval policy
- Current desktop screenshots as MCP images, downloadable Action files, or signed temporary URLs
- Local Tesseract OCR with confidence scores and bounding boxes
- Persistent Playwright Chromium profile with ARIA/DOM snapshots and semantic locators
- Browser tabs, navigation, upload, download, screenshots, console messages, and page errors
- Windows UI Automation for native applications
- Mouse, keyboard, clipboard, and window control
- Text/binary filesystem operations and recursive deletion in Full mode
- Synchronous commands and detached command jobs with polling/cancellation
- Process-tree control
- Registry, services, packages, network, scheduled tasks, and power controls
- Append-only secret-redacted audit log
- STOP-file kill switch independent of the model
- DPAPI-encrypted Action key storage
- Optional highest-privilege interactive autostart task
- Quick Tunnel and named Cloudflare Tunnel helpers
- Installation and diagnostics scripts

## ChatGPT Pro connection path

ChatGPT Pro can build and use private GPTs with Actions, but Actions are not available in Pro model
mode. Select an Action-compatible model in the custom GPT editor. The bridge does not call the OpenAI
API, so it creates no OpenAI API token charges.

The practical path is:

```text
Private Custom GPT
        ↓ GPT Action over HTTPS + Bearer key
Cloudflare tunnel / authenticated reverse proxy
        ↓ localhost
Desktop Action Gateway
        ↓
Windows + managed browser + filesystem + terminal
```

The MCP server remains available for MCP clients that support the needed read/write tools.

## Requirements

- Windows 10 or Windows 11
- An interactive logged-in desktop session
- Python 3.11 or newer; the installer can install Python with WinGet
- Administrator PowerShell for OS-wide Full-mode operations and highest-privilege autostart
- A private Custom GPT for the no-API-cost ChatGPT path

## One-command bootstrap

Open **PowerShell as Administrator**:

```powershell
git clone https://github.com/Emad211/Desktop-MCP-Bridge.git
cd Desktop-MCP-Bridge
git switch feat/initial-desktop-bridge
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\bootstrap.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -StartNow `
  -RunSelfTest `
  -IUnderstand
```

This performs the following:

1. creates/updates `.venv`;
2. installs the bridge and development checks;
3. installs managed Chromium for Playwright;
4. installs Tesseract OCR when missing;
5. generates a strong Action key;
6. stores the key encrypted for the current Windows user with DPAPI;
7. writes the chosen profile and approval policy into local bootstrap metadata;
8. optionally installs an interactive logon scheduled task.

The key is printed once and is also stored at:

```text
%LOCALAPPDATA%\DesktopMCPBridge\action-key.clixml
```

## Start the Action Gateway

Full Autonomous mode:

```powershell
.\scripts\run-actions.ps1 -FullAccess -Autonomous -IUnderstand
```

Full Guarded mode:

```powershell
.\scripts\run-actions.ps1 -FullAccess -IUnderstand
```

The server listens only on:

```text
http://127.0.0.1:8766
```

### Temporary HTTPS tunnel for testing

Open a second PowerShell:

```powershell
.\scripts\run-quick-tunnel.ps1 -Port 8766 -InstallIfMissing
```

Quick Tunnel URLs change whenever the tunnel restarts. For a stable hostname:

```powershell
.\scripts\setup-named-tunnel.ps1 `
  -TunnelName desktop-agent `
  -Hostname desktop-agent.example.com `
  -InstallIfMissing
```

## Configure the private GPT

1. Create a private GPT.
2. Choose a model that supports Actions.
3. Copy `gpt/INSTRUCTIONS.md` into the GPT instructions.
4. Add an Action and import `gpt-actions.openapi.yaml`.
5. Replace `https://YOUR_PUBLIC_HTTPS_HOST` with the tunnel URL/hostname.
6. Choose API Key authentication in Bearer format.
7. Paste the generated key.
8. Keep the GPT private.
9. Test `healthCheck`, `observeComputer`, and `getScreenCapture`.

## Access profiles

| Capability | Safe | Developer | Full |
|---|:---:|:---:|:---:|
| Desktop screenshot/input | ✓ | ✓ | ✓ |
| Windows UI Automation | ✓ | ✓ | ✓ |
| OCR | ✓ | ✓ | ✓ |
| Managed browser | ✓ | ✓ | ✓ |
| Files under configured roots | ✓ | ✓ | ✓ |
| Files anywhere allowed by Windows | — | — | ✓ |
| Allowlisted shell | ✓ | ✓ | — |
| Unrestricted shell | — | — | ✓ |
| Delete files | — | ✓ | ✓ |
| Recursive delete | — | — | ✓ |
| Process termination | — | ✓ | ✓ |
| Clipboard | — | ✓ | ✓ |
| Registry/services/packages/network/tasks/power | — | — | ✓ |

Full mode requires both:

```text
DMB_ACCESS_PROFILE=full
DMB_FULL_ACCESS_CONFIRMATION=I UNDERSTAND THIS GRANTS FULL CONTROL
```

It removes bridge-level path and command restrictions but does not bypass Windows ACLs, UAC, account
separation, or endpoint protection.

## Guarded versus Autonomous

`DMB_APPROVAL_POLICY=guarded` requires an extra `CONFIRM:<operation>` value for high-risk Action calls.
`autonomous` removes that extra bridge prompt while retaining ChatGPT's consequential Action UI,
idempotency, audit logs, and the local kill switch.

## Idempotent Action calls

Every `/v1/act` request requires `request_id`.

- Generate a new UUID for each logical action.
- Reuse it only to retry the exact same request after a timeout.
- The bridge returns the cached result instead of executing twice.
- Reusing an ID with different arguments is rejected.

This is especially important for file deletion, package installation, process termination, and command
jobs.

## Desktop vision

### Direct screenshot

`getScreenCapture` returns the current monitor as PNG.

### Signed screenshot artifact

`capture_desktop_artifact` stores a short-lived local image and returns a signed URL. The URL is
unguessable, expires automatically, and does not expose a permanent unauthenticated file route.

### OCR

`screen_ocr` returns:

- extracted text;
- confidence per token;
- x/y/width/height bounding boxes;
- monitor/capture geometry;
- optional screenshot artifact.

Use OCR when native UI Automation does not expose the text. Use coordinate clicks only against a
current capture, never an old screen.

## Managed browser

The browser has its own persistent profile under the per-user bridge state directory. It does not
silently share the normal Chrome password manager or profile.

Recommended loop:

```text
browser_start
→ browser_navigate
→ browser_snapshot
→ browser_interact
→ browser_snapshot or browser_screenshot
```

Selectors:

```json
{"kind":"role","role":"button","name":"Submit"}
{"kind":"label","value":"Email"}
{"kind":"text","value":"Download","exact":true}
{"kind":"placeholder","value":"Search"}
{"kind":"testid","value":"save-button"}
{"kind":"css","value":"#save"}
```

Supported interactions include click, double-click, fill, sequential type, press, check, uncheck,
select, hover, and focus. The snapshot includes an ARIA representation, visible interactive elements,
console messages, and page errors.

## Native Windows applications

Prefer semantic automation:

```text
list_windows → uia_tree → uia_invoke → uia_tree
```

Use `desktop_step` only when an application does not expose useful UI Automation elements.

## Long-running commands

Do not run builds or installers synchronously through GPT Actions. Use:

```text
start_command_job → get_command_job → get_command_job ...
```

The job output is persisted under the per-user bridge state directory and can be cancelled, including
its process tree.

## Kill switch

Block all mutating operations immediately:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

Inspect or re-enable:

```powershell
.\scripts\kill-switch.ps1 -Mode Status
.\scripts\kill-switch.ps1 -Mode Disable
```

Read-only status and audit tools remain available for diagnosis.

## Diagnostics

```powershell
.\scripts\diagnose.ps1 -TestScreen
```

Diagnostics check installation, imports, OpenAPI generation, Tesseract, Playwright browser files,
encrypted key presence, port usage, administrator state, kill switch state, and optional live capture.


## Operational lifecycle

Start the gateway in the background and wait for health:

```powershell
.\scripts\start-gateway.ps1 -FullAccess -Autonomous -IUnderstand
```

Inspect all local state:

```powershell
.\scripts\status.ps1
```

Run an end-to-end test against the live gateway:

```powershell
.\scripts\self-test.ps1
```

Start/stop a machine-readable Quick Tunnel:

```powershell
$Tunnel = .\scripts\start-quick-tunnel.ps1 -InstallIfMissing | ConvertFrom-Json
.\scripts\stop-quick-tunnel.ps1
```

Generate ready-to-import GPT files for that URL:

```powershell
.\scripts\export-gpt-config.ps1 -PublicBaseUrl $Tunnel.url
```

Stop the gateway process tree:

```powershell
.\scripts\stop-gateway.ps1
```

The complete Persian installation prompt for a local desktop agent is stored in
`docs/DESKTOP_AGENT_INSTALL_PROMPT_FA.md`.

## MCP usage

Safe/developer profile:

```powershell
.\scripts\run.ps1 -AllowedRoot "D:\AI-Workspace" -Profile developer
```

Full profile:

```powershell
.\scripts\run-full-mcp.ps1 -Transport stdio -IUnderstand
```

## Security boundaries

- No credential dumping, keylogging, endpoint-protection bypass, hidden persistence, or stealth tools.
- PyAutoGUI's upper-left-corner fail-safe remains active.
- The Action gateway binds to localhost by default.
- Bearer authentication does not replace HTTPS.
- Artifact links are signed and short-lived.
- Audit records redact common password/token/API-key fields and matching command-line patterns.
- Autostart is an explicit visible Scheduled Task and can be removed with
  `scripts/uninstall-autostart.ps1`.
- Use a separate Windows account or VM for highly autonomous work that should not reach personal data.

See `SECURITY.md`, `docs/THREAT_MODEL.md`, and `docs/PRIVACY.md`.

## Testing

```powershell
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest --cov=desktop_mcp_bridge --cov-report=term-missing
```

GitHub Actions runs the suite on Windows with Python 3.11 and 3.12.

## License

MIT
