# Changelog

## 1.1.0

- Added self-elevating bootstrap and deployment repair with UAC handoff.
- Preserved existing DPAPI Action keys unless explicit rotation is requested.
- Added managed Chromium fallback to installed Microsoft Edge and Google Chrome when the Playwright CDN is blocked.
- Added automatic Tesseract discovery on every runtime start.
- Added V2Ray, WinINET, WinHTTP, environment, PAC, and common loopback proxy detection.
- Added direct/proxy route probing and multi-provider tunnel selection.
- Added proxy-aware ngrok and Cloudflare tunnel launchers.
- Added stable Tailscale Funnel support and explicit VPN-conflict guidance.
- Added a tunnel supervisor that recovers after VPN/network transitions.
- Added unified tunnel state, public endpoint verification, endpoint-change reporting, and tunnel autostart.
- Added a self-elevating repair workflow for Gateway, Autostart, Browser, OCR, Tunnel, and GPT config export.
- Expanded diagnostics and status output for browser backends, VPN routes, public health, and scheduled tasks.
- Added browser fallback unit tests and Windows PowerShell compatibility fixes.

## 1.0.0

- Added private GPT Action Gateway with Bearer authentication.
- Added Safe, Developer, and explicit Full access profiles.
- Added Guarded and Autonomous approval policies.
- Added persistent request idempotency for write retries.
- Added short-lived signed screenshot/browser artifacts.
- Added desktop OCR with English and Persian language installation.
- Added managed persistent Playwright Chromium with semantic selectors and ARIA snapshots.
- Added Windows UI Automation, mouse, keyboard, window, and clipboard control.
- Added text/binary file operations, shell commands, detached jobs, and process-tree control.
- Added registry, service, package, network, scheduled task, and power administration.
- Added DPAPI key storage, autostart, diagnostics, self-test, status, lifecycle, tunnel, export, key
  rotation, and uninstall scripts.
- Added append-only secret-redacted auditing and local STOP-file kill switch.
- Added Windows CI for Python 3.11/3.12 and PowerShell parser validation.
