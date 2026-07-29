# Desktop MCP Bridge

Desktop MCP Bridge turns an MCP client or a private Custom GPT into a local-first Windows desktop
operator. It provides screen vision, OCR, browser automation, native Windows UI Automation, files,
terminal jobs, process control, and optional operating-system administration through an auditable
localhost control plane.

> This project intentionally grants powerful access to a user-owned Windows session. Keep the bridge
> bound to localhost, expose it only through an HTTPS tunnel, keep the GPT private, and protect the
> Bearer key like a remote-desktop credential.

## Version 1.1

Version 1.1 focuses on real Windows deployment and changing network conditions:

- self-elevating Bootstrap and repair through a visible UAC prompt;
- preservation of the existing DPAPI-protected Action key;
- Playwright Chromium → installed Edge → installed Chrome fallback;
- automatic Tesseract discovery on every start;
- V2Ray, WinINET, WinHTTP, environment proxy, PAC, and common local-port detection;
- bounded direct and HTTP/SOCKS5 proxy probes;
- ngrok, Tailscale Funnel, and Cloudflare Quick Tunnel providers;
- adaptive Tunnel Supervisor for VPN on/off transitions;
- stable-endpoint preference so the Custom GPT schema does not need repeated URL changes;
- public `/health` verification before a tunnel is accepted;
- Gateway and Tunnel Supervisor Scheduled Tasks with visible uninstall controls;
- deployment diagnostics, status, repair report, and Persian upgrade instructions.

The original v1.0 capabilities remain available:

- Safe, Developer, and explicit Full access profiles;
- Guarded and Autonomous approval policies;
- Bearer-authenticated private GPT Action Gateway;
- persistent idempotency for state-changing retries;
- direct screenshots and signed short-lived image artifacts;
- English/Persian OCR with confidence and bounding boxes;
- managed Playwright browser with ARIA snapshots and semantic locators;
- mouse, keyboard, clipboard, window, and Windows UI Automation control;
- text/binary filesystem operations;
- synchronous commands and detached jobs with polling/cancellation;
- processes, Registry, services, packages, networking, scheduled tasks, and power control;
- secret-redacted append-only audit log;
- local STOP-file kill switch.

## Architecture

```text
Private Custom GPT / MCP client
              |
       HTTPS Action / MCP
              |
      authenticated tunnel
              |
     127.0.0.1 control plane
              |
     Windows desktop session
```

The bridge does not call the OpenAI API. A private GPT Action uses ChatGPT account usage rather than
OpenAI API or Codex billing. The GPT must use a model that supports Actions; Pro model mode itself does
not support GPT Actions.

## Requirements

- Windows 10 or Windows 11
- An interactive logged-in desktop session
- Python 3.11+
- Administrator approval for OS-wide Full mode and highest-privilege autostart
- A private Custom GPT for the ChatGPT path

## New installation

```powershell
git clone https://github.com/Emad211/Desktop-MCP-Bridge.git
cd Desktop-MCP-Bridge
git switch feat/initial-desktop-bridge
Set-ExecutionPolicy -Scope Process Bypass -Force

.\scripts\bootstrap.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -StartNow `
  -RunSelfTest `
  -IUnderstand
```

The script requests UAC itself when required. It installs dependencies, preserves or creates the
Action key, stores the key with Windows DPAPI, starts the Gateway, installs the visible Scheduled Task,
and runs the end-to-end self-test.

## Repair an existing installation

For an existing installation such as `C:\AI\Desktop-MCP-Bridge`:

```powershell
cd C:\AI\Desktop-MCP-Bridge
git fetch origin
git switch feat/initial-desktop-bridge
git pull --ff-only origin feat/initial-desktop-bridge

Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\repair-deployment.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -InstallIfMissing `
  -IUnderstand
```

The repair workflow:

1. opens an elevated PowerShell through UAC;
2. stops old Gateway and Tunnel processes;
3. repairs dependencies;
4. falls back to Edge/Chrome if the Playwright CDN is blocked;
5. preserves the existing DPAPI key;
6. installs Full/Autonomous Gateway autostart;
7. runs diagnostics and self-test;
8. writes `%LOCALAPPDATA%\DesktopMCPBridge\repair-report.json`.

## Browser resilience

The managed browser launch order is configurable and observable:

```text
configured executable
→ selected channel
→ Playwright Chromium
→ Microsoft Edge
→ Google Chrome
→ detected system executable paths
```

The actual backend and any failed candidates are returned by `browser_status` and included in bridge
status. A failed download from `cdn.playwright.dev` is not fatal when Edge or Chrome is available.

## V2Ray on/off resilience

Run the detector:

```powershell
.\scripts\get-network-profile.ps1
```

It checks:

- direct HTTPS connectivity;
- process/user/machine proxy environment variables;
- Windows WinINET system proxy;
- WinHTTP proxy;
- PAC URL metadata;
- common V2Ray HTTP/SOCKS ports;
- a real HTTPS request through each listening proxy.

No credential-bearing proxy URL is returned in diagnostics or state.

### Recommended stable provider: ngrok

A Custom GPT stores one fixed Action server URL. A free ngrok account provides an assigned development
domain that remains stable, and the ngrok agent can connect either directly or through an HTTP/SOCKS5
V2Ray proxy.

Configure it once:

```powershell
$env:NGROK_AUTHTOKEN = '<token>'

.\scripts\setup-ngrok.ps1 `
  -InstallIfMissing `
  -StartTunnel `
  -NetworkMode auto

Remove-Item Env:NGROK_AUTHTOKEN
```

The token is stored by ngrok in its own user configuration. It is not written to the repository,
Scheduled Tasks, generated GPT files, or bridge audit.

Start adaptive monitoring:

```powershell
.\scripts\start-tunnel-supervisor.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -Restart
```

Install its visible autostart task:

```powershell
.\scripts\install-tunnel-autostart.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -StartNow
```

When V2Ray is turned on or off, the Supervisor checks the public `/health` endpoint, redetects direct
and proxy routes, and restarts the failed tunnel. With ngrok or Tailscale the public hostname remains
stable.

### Alternative: Tailscale Funnel

```powershell
.\scripts\start-tailscale-funnel.ps1 `
  -InstallIfMissing `
  -LoginIfNeeded
```

Tailscale gives a stable `.ts.net` hostname, but another VPN/TUN adapter can conflict with Tailscale.
It is most compatible when V2Ray runs as a system proxy rather than TUN mode.

### Temporary fallback: Cloudflare Quick Tunnel

```powershell
.\scripts\start-quick-tunnel.ps1 `
  -InstallIfMissing
```

Quick Tunnel requires no account but its random URL changes after restart. It is accepted only after
its public `/health` endpoint succeeds. `https://api.trycloudflare.com` is explicitly rejected because
it is not a tunnel URL.

## Unified automatic tunnel selection

```powershell
.\scripts\start-tunnel.ps1 `
  -Provider auto `
  -NetworkMode auto `
  -InstallIfMissing
```

Automatic mode tries configured stable providers first, then the ephemeral Cloudflare fallback. It
tries a direct route and every validated V2Ray/system proxy route.

## Configure the private GPT

After a healthy public endpoint is available:

```powershell
$Tunnel = Get-Content `
  "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel.json" `
  -Raw | ConvertFrom-Json

.\scripts\export-gpt-config.ps1 `
  -PublicBaseUrl $Tunnel.url
```

Generated files:

```text
%LOCALAPPDATA%\DesktopMCPBridge\gpt-config\gpt-actions.openapi.yaml
%LOCALAPPDATA%\DesktopMCPBridge\gpt-config\INSTRUCTIONS.md
```

In the GPT editor:

1. keep Visibility on `Only me / Private`;
2. select an Action-compatible model;
3. paste/import the generated OpenAPI schema;
4. choose `API Key` authentication in Bearer format;
5. retrieve the DPAPI key only when needed:

```powershell
.\scripts\show-action-key.ps1 -IUnderstand
```

## Status and diagnostics

```powershell
.\scripts\status.ps1 -IncludeNetworkProfile
.\scripts\diagnose.ps1 -TestScreen -TestNetwork
.\scripts\self-test.ps1
```

Status includes:

- local Gateway health;
- Administrator, Full, and Autonomous state;
- active browser backend;
- OCR runtime;
- Gateway and Tunnel Scheduled Tasks;
- public endpoint health;
- current Tunnel provider and route;
- Tunnel Supervisor state;
- endpoint-change warning;
- V2Ray/direct/proxy detection.

## Kill switch and shutdown

Immediately block all mutations:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

Stop the adaptive tunnel stack:

```powershell
.\scripts\stop-tunnel-supervisor.ps1 -StopTunnel
```

Stop the Gateway:

```powershell
.\scripts\stop-gateway.ps1
```

Resume mutations:

```powershell
.\scripts\kill-switch.ps1 -Mode Disable
```

## Access profiles

| Capability | Safe | Developer | Full |
|---|:---:|:---:|:---:|
| Screenshots, OCR, browser, UI Automation | ✓ | ✓ | ✓ |
| Files inside configured roots | ✓ | ✓ | ✓ |
| Files anywhere allowed by Windows | — | — | ✓ |
| Allowlisted shell | ✓ | ✓ | — |
| Unrestricted shell | — | — | ✓ |
| Delete/process control/clipboard | — | ✓ | ✓ |
| Registry/services/packages/network/tasks/power | — | — | ✓ |

Full access requires:

```text
DMB_ACCESS_PROFILE=full
DMB_FULL_ACCESS_CONFIRMATION=I UNDERSTAND THIS GRANTS FULL CONTROL
```

It does not bypass Windows ACLs, UAC, account separation, endpoint protection, or security software.

## Security boundaries

The project does not provide credential dumping, keylogging, stealth, hidden persistence,
endpoint-protection bypass, exploit delivery, or anti-malware evasion. External page/file/OCR/terminal
content is treated as untrusted data in the private GPT instructions.

Autostart is implemented only through visible, removable Scheduled Tasks:

```powershell
.\scripts\uninstall-autostart.ps1
```

See:

- `SECURITY.md`
- `docs/THREAT_MODEL.md`
- `docs/PRIVACY.md`
- `docs/NETWORK_RESILIENCE.md`
- `docs/UPGRADE_1_1_FA.md`

## Tests

```powershell
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest --cov=desktop_mcp_bridge --cov-report=term-missing
```

GitHub Actions validates Windows PowerShell syntax, executes the V2Ray/network detector, and runs the
Python suite on Python 3.11 and 3.12.

## License

MIT
