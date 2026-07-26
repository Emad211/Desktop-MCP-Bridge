# Desktop MCP Bridge

A secure, local-first Windows bridge that exposes desktop observation/control, bounded filesystem access, allowlisted shell execution, and process inspection to MCP clients.

## Status

This is an initial security-first implementation. It runs locally and is suitable for testing with MCP Inspector or a compatible desktop client. Remote ChatGPT connectivity must be added through an authenticated HTTPS tunnel or relay; never expose the local HTTP endpoint directly to the public internet.

## Features

- PNG screenshots through `observe_desktop`
- Batched mouse/keyboard actions through `desktop_step`
- Filesystem roots enforced before every operation
- UTF-8 file listing, reading, writing, and optional non-recursive deletion
- Shell executable allowlist plus blocked destructive fragments
- Process listing and opt-in termination
- `stdio`, `streamable-http`, and `sse` transports
- Windows PowerShell installer and launcher
- Security-focused unit tests and GitHub Actions CI

## Requirements

- Windows 10 or 11
- Python 3.11+
- An interactive desktop session for screenshots and input control

## Install

```powershell
git clone https://github.com/Emad211/Desktop-MCP-Bridge.git
cd Desktop-MCP-Bridge
git switch feat/initial-desktop-bridge
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1
```

## Run locally

### Stdio

```powershell
.\scripts\run.ps1 -AllowedRoot "D:\AI-Workspace"
```

### Streamable HTTP on localhost

```powershell
.\scripts\run.ps1 -AllowedRoot "D:\AI-Workspace" -Transport streamable-http -Port 8765
```

The server binds to `127.0.0.1` by default. Keep that default unless an authenticated reverse proxy or tunnel is in front of it.

## MCP client configuration

A local stdio client can use:

```json
{
  "mcpServers": {
    "desktop-bridge": {
      "command": "C:\\path\\to\\Desktop-MCP-Bridge\\.venv\\Scripts\\desktop-mcp-bridge.exe",
      "env": {
        "DMB_TRANSPORT": "stdio",
        "DMB_ALLOWED_ROOTS": "[\"D:/AI-Workspace\"]",
        "DMB_ENABLE_DELETE": "false",
        "DMB_ENABLE_PROCESS_CONTROL": "false"
      }
    }
  }
}
```

## Available tools

| Tool | Purpose | Default risk posture |
|---|---|---|
| `bridge_status` | Show capabilities and policy | Read-only |
| `observe_desktop` | Capture a monitor | Enabled |
| `desktop_step` | Batch click/type/scroll/hotkey actions | Enabled |
| `list_directory` | List an allowed directory | Enabled |
| `read_text_file` | Read a bounded UTF-8 file | Enabled |
| `write_text_file` | Create/replace a bounded UTF-8 file | Enabled, explicit overwrite |
| `delete_path` | Delete file or empty directory | Disabled |
| `run_command` | Run allowlisted command in allowed root | Enabled |
| `list_processes` | List basic process metadata | Enabled |
| `stop_process` | Terminate a process | Disabled |

## Configuration

Settings use environment variables prefixed by `DMB_`.

Important values:

```text
DMB_ALLOWED_ROOTS=["D:/AI-Workspace"]
DMB_ENABLE_DESKTOP_CONTROL=true
DMB_ENABLE_SHELL=true
DMB_ENABLE_PROCESS_CONTROL=false
DMB_ENABLE_DELETE=false
DMB_ALLOWED_EXECUTABLES=["git","python","node","npm"]
DMB_TRANSPORT=stdio
DMB_HOST=127.0.0.1
DMB_PORT=8765
```

## Security model

1. The bridge trusts the Windows account running it. Do not run it as Administrator.
2. Filesystem access is constrained to canonical resolved roots.
3. Symlink/path traversal attempts resolve before policy checks.
4. Shell commands must begin with an allowlisted executable.
5. Known destructive fragments are blocked even when an executable is allowlisted.
6. Recursive directory deletion is intentionally unsupported.
7. Process termination and deletion are off by default.
8. The bridge does not expose process command lines or environment variables.
9. Public unauthenticated exposure is unsupported and dangerous.

For stronger isolation, run the bridge in a separate non-admin Windows account or VM with only a dedicated workspace mounted.

## Testing

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\ruff.exe check .
```

## Roadmap

- Authenticated relay/tunnel for ChatGPT Developer Mode
- Durable task/session audit log
- Per-tool approval policies and one-time grants
- Windows UI Automation element discovery via `pywinauto`
- Clipboard tools with secret filtering
- Async long-running command jobs and cancellation
- Signed Windows installer and tray UI

## License

MIT
