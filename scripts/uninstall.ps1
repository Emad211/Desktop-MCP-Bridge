param(
    [switch]$RemoveVirtualEnvironment,
    [switch]$RemoveLocalState,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $PSScriptRoot "stop-quick-tunnel.ps1") -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot "stop-gateway.ps1") -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot "uninstall-autostart.ps1") -ErrorAction SilentlyContinue

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
    autostart_removed = $true
    virtual_environment_removed = [bool]$RemoveVirtualEnvironment
    local_state_removed = [bool]$RemoveLocalState
} | ConvertTo-Json
