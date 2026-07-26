# Changelog

## 1.2.0

- Added a detached UAC elevation broker so desktop agents do not time out while waiting for consent.
- Added machine-readable repair progress and repair status polling with stable run IDs.
- Added transactional gateway shutdown with listener verification and exact remaining-PID errors.
- Added single-instance gateway startup with authenticated profile, policy, privilege, and process-tree verification.
- Added gateway PID and process start time to authenticated runtime status.
- Separated caller privilege from actual gateway privilege in status output.
- Changed gateway autostart to use verified single-instance startup instead of directly launching the server.
- Made Full repair require a verified Administrator gateway before completion.
- Added final listener/state/PID consistency checks to deployment repair.
- Fixed diagnostic output contamination that produced `Invalid JSON primitive: imports.`.
- Added robust terminal-JSON extraction for nested deployment scripts.
- Added CI validation for machine-readable diagnostics and gateway process identity.

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
