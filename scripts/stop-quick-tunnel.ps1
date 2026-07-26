param([string]$StatePath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\quick-tunnel.json"))

$ErrorActionPreference = "Continue"
$ProcessId = $null
if (Test-Path $StatePath) {
    try { $ProcessId = (Get-Content $StatePath -Raw | ConvertFrom-Json).pid } catch {}
}
if ($ProcessId) {
    & taskkill.exe /PID $ProcessId /T /F | Out-Null
}
Remove-Item $StatePath -Force -ErrorAction SilentlyContinue
[ordered]@{ stopped = $true; pid = $ProcessId } | ConvertTo-Json
