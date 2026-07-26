param(
    [switch]$RemoveVirtualEnvironment,
    [switch]$RemoveLocalState,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $PSScriptRoot "stop-tunnel-supervisor.ps1") -StopTunnel -ErrorAction SilentlyContinue | Out-Null
& (Join-Path $PSScriptRoot "stop-gateway.ps1") -ErrorAction SilentlyContinue | Out-Null
& (Join-Path $PSScriptRoot "uninstall-autostart.ps1") -ErrorAction SilentlyContinue | Out-Null

if (($RemoveVirtualEnvironment -or $RemoveLocalState) -and -not $IUnderstand) {
    throw "Deleting the virtual environment or local state requires -IUnderstand."
}
if ($RemoveVirtualEnvironment) {
    Remove-Item (Join-Path $RepoRoot ".venv") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $RepoRoot ".playwright-browsers") -Recurse -Force -ErrorAction SilentlyContinue
}
if ($RemoveLocalState) {
    Remove-Item (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge") -Recurse -Force -ErrorAction SilentlyContinue
}
[ordered]@{
    stopped = $true
    tunnel_supervisor_stopped = $true
    tunnel_stopped = $true
    autostart_removed = $true
    virtual_environment_removed = [bool]$RemoveVirtualEnvironment
    local_state_removed = [bool]$RemoveLocalState
} | ConvertTo-Json
