param([switch]$StopTunnel)

$ErrorActionPreference = "Continue"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$StatePath = Join-Path $StateDir "tunnel-supervisor.json"
$StopPath = Join-Path $StateDir "TUNNEL_STOP"
New-Item -ItemType File -Path $StopPath -Force | Out-Null
$ProcessId = $null
if (Test-Path $StatePath) {
    try { $ProcessId = (Get-Content $StatePath -Raw | ConvertFrom-Json).pid } catch {}
}
if ($ProcessId -and $ProcessId -ne $PID) {
    for ($Index = 0; $Index -lt 10; $Index++) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        & taskkill.exe /PID $ProcessId /T /F | Out-Null
    }
}
if ($StopTunnel) {
    & (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
}
[ordered]@{
    stopped = $true
    pid = $ProcessId
    tunnel_stopped = [bool]$StopTunnel
} | ConvertTo-Json
