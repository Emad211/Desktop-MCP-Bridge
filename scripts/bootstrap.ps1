param(
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$InstallAutostart,
    [switch]$StartNow,
    [switch]$RunSelfTest,
    [switch]$SkipBrowser,
    [switch]$SkipOCR,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

if ($FullAccess -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand. It grants the bridge all permissions available to this Windows session."
}

& (Join-Path $PSScriptRoot "install.ps1") -SkipBrowser:$SkipBrowser -SkipOCR:$SkipOCR

$Key = & (Join-Path $PSScriptRoot "new-action-key.ps1")
& (Join-Path $PSScriptRoot "save-action-key.ps1") -ApiKey $Key

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$Config = [ordered]@{
    repo_root = $RepoRoot
    profile = $(if ($FullAccess) { "full" } else { "safe" })
    approval_policy = $(if ($Autonomous) { "autonomous" } else { "guarded" })
    action_port = 8766
    created_at = (Get-Date).ToUniversalTime().ToString("o")
}
$Config | ConvertTo-Json | Set-Content -Path (Join-Path $StateDir "bootstrap.json") -Encoding UTF8

if ($InstallAutostart) {
    & (Join-Path $PSScriptRoot "install-autostart.ps1") -FullAccess:$FullAccess -Autonomous:$Autonomous -IUnderstand:$IUnderstand
}

Write-Host "" 
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host "Action key (shown once; also stored encrypted with DPAPI):" -ForegroundColor Yellow
Write-Host $Key -ForegroundColor White
Write-Host "" 
Write-Host "Start command:" -ForegroundColor Cyan
$Command = ".\scripts\run-actions.ps1"
if ($FullAccess) { $Command += " -FullAccess -IUnderstand" }
if ($Autonomous) { $Command += " -Autonomous" }
Write-Host $Command

if ($StartNow) {
    & (Join-Path $PSScriptRoot "start-gateway.ps1") -FullAccess:$FullAccess -Autonomous:$Autonomous -IUnderstand:$IUnderstand
}
if ($RunSelfTest) {
    if (-not $StartNow) {
        & (Join-Path $PSScriptRoot "start-gateway.ps1") -FullAccess:$FullAccess -Autonomous:$Autonomous -IUnderstand:$IUnderstand
    }
    & (Join-Path $PSScriptRoot "self-test.ps1")
}
