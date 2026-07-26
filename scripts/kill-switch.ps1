param(
    [ValidateSet("Enable", "Disable", "Status")]
    [string]$Mode = "Status"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}

$path = & .\.venv\Scripts\python.exe -c "from desktop_mcp_bridge.config import BridgeSettings; print(BridgeSettings().kill_switch_path)"
switch ($Mode) {
    "Enable" {
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        Set-Content -Path $path -Value "STOP" -NoNewline
        Write-Host "Kill switch enabled: $path" -ForegroundColor Red
    }
    "Disable" {
        Remove-Item -Force -ErrorAction SilentlyContinue $path
        Write-Host "Kill switch disabled: $path" -ForegroundColor Green
    }
    "Status" {
        Write-Output ([pscustomobject]@{ Path = $path; Enabled = (Test-Path $path) })
    }
}
