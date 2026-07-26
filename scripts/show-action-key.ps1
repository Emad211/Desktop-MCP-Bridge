param(
    [string]$Path = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml"),
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
if (-not $IUnderstand) {
    throw "Revealing the bearer key requires -IUnderstand. Anyone with this key and the HTTPS endpoint can control the bridge."
}
if (-not (Test-Path $Path)) {
    throw "Encrypted Action key not found: $Path"
}
$Credential = Import-Clixml -Path $Path
Write-Output $Credential.GetNetworkCredential().Password
