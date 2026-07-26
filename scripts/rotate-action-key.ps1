param(
    [switch]$RestartGateway,
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$IUnderstand,
    [switch]$Reveal
)

$ErrorActionPreference = "Stop"
if ($FullAccess -and -not $IUnderstand) { throw "Full access restart requires -IUnderstand." }
$Key = & (Join-Path $PSScriptRoot "new-action-key.ps1")
& (Join-Path $PSScriptRoot "save-action-key.ps1") -ApiKey $Key
if ($RestartGateway) {
    & (Join-Path $PSScriptRoot "start-gateway.ps1") -Restart -FullAccess:$FullAccess -Autonomous:$Autonomous -IUnderstand:$IUnderstand
}
Write-Host "Action key rotated. Update the Bearer key in the private GPT before its next call." -ForegroundColor Yellow
if ($Reveal) { Write-Output $Key }
