param(
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tunnel.json")
)

$ErrorActionPreference = "Continue"
$State = $null
if (Test-Path $StatePath) {
    try { $State = Get-Content $StatePath -Raw | ConvertFrom-Json } catch {}
}

if ($State) {
    if ($State.provider -eq "tailscale-funnel" -and (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        & tailscale funnel --https=443 off | Out-Null
    }
    if ($State.pid -and $State.pid -ne $PID) {
        & taskkill.exe /PID $State.pid /T /F | Out-Null
    }
}

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
Remove-Item $StatePath -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StateDir "quick-tunnel.json") -Force -ErrorAction SilentlyContinue
[ordered]@{
    stopped = $true
    provider = if ($State) { $State.provider } else { $null }
    pid = if ($State) { $State.pid } else { $null }
} | ConvertTo-Json -Depth 5
