param(
    [string]$ApiKey = $env:DMB_ACTION_API_KEY,
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml"),
    [int]$Port = 8766,
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "safe",
    [string[]]$AllowedRoot = @((Get-Location).Path),
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}

if ([string]::IsNullOrWhiteSpace($ApiKey) -and (Test-Path $EncryptedKeyPath)) {
    $Credential = Import-Clixml -Path $EncryptedKeyPath
    $ApiKey = $Credential.GetNetworkCredential().Password
}
if ([string]::IsNullOrWhiteSpace($ApiKey) -or $ApiKey.Length -lt 32) {
    throw "No valid key found. Run .\scripts\bootstrap.ps1 or provide -ApiKey."
}

if ($FullAccess) { $Profile = "full" }
if ($Profile -eq "full" -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand."
}

$Roots = @()
foreach ($Root in $AllowedRoot) {
    $Roots += ((Resolve-Path $Root).Path -replace '\\', '/')
}
$env:DMB_ALLOWED_ROOTS = ($Roots | ConvertTo-Json -Compress)
$env:DMB_ACCESS_PROFILE = $Profile
$env:DMB_ACTION_HOST = "127.0.0.1"
$env:DMB_ACTION_PORT = "$Port"
$env:DMB_ACTION_API_KEY = $ApiKey
$env:DMB_APPROVAL_POLICY = $(if ($Autonomous) { "autonomous" } else { "guarded" })
$env:PLAYWRIGHT_BROWSERS_PATH = (Join-Path $RepoRoot ".playwright-browsers")
$env:DMB_TESSDATA_DIR = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tessdata")

$TesseractCandidates = @(
    "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
    "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
    "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe"
) | Where-Object { $_ -and (Test-Path $_) }
if ($TesseractCandidates) { $env:DMB_TESSERACT_COMMAND = $TesseractCandidates[0] }

if ($Profile -eq "full") {
    $env:DMB_FULL_ACCESS_CONFIRMATION = "I UNDERSTAND THIS GRANTS FULL CONTROL"
    $Admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $Admin) {
        Write-Warning "Full profile is active, but Administrator-only operations will fail because this terminal is not elevated."
    }
}

Write-Host "Desktop Action Gateway v1.0 starting on 127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "Profile: $Profile | Approval policy: $env:DMB_APPROVAL_POLICY" -ForegroundColor Cyan
Write-Host "Keep this window open. Use the STOP-file kill switch for emergency shutdown of mutations." -ForegroundColor Yellow
& .\.venv\Scripts\python.exe -m desktop_mcp_bridge actions
