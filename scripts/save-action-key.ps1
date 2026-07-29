param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$Path = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml")
)

$ErrorActionPreference = "Stop"
if ($ApiKey.Length -lt 32) { throw "The Action API key must contain at least 32 characters." }
$Directory = Split-Path -Parent $Path
New-Item -ItemType Directory -Path $Directory -Force | Out-Null
$Secure = ConvertTo-SecureString $ApiKey -AsPlainText -Force
$Credential = [PSCredential]::new("DesktopMCPBridge", $Secure)
$Credential | Export-Clixml -Path $Path -Force
Write-Host "Action key stored with Windows DPAPI for the current user: $Path" -ForegroundColor Green
