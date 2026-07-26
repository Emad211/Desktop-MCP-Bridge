param(
    [string]$ApiKey = $env:DMB_ACTION_API_KEY,
    [int]$Port = 8766,
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "safe",
    [string[]]$AllowedRoot = @((Get-Location).Path),
    [switch]$FullAccess,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}
if ([string]::IsNullOrWhiteSpace($ApiKey) -or $ApiKey.Length -lt 32) {
    throw "Provide a random API key of at least 32 characters with -ApiKey or DMB_ACTION_API_KEY."
}

if ($FullAccess) {
    $Profile = "full"
}
if ($Profile -eq "full" -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand. It can read/write/delete across the account and run unrestricted commands."
}

$roots = @()
foreach ($root in $AllowedRoot) {
    $resolved = (Resolve-Path $root).Path -replace '\\', '/'
    $roots += $resolved
}
$env:DMB_ALLOWED_ROOTS = ($roots | ConvertTo-Json -Compress)
$env:DMB_ACCESS_PROFILE = $Profile
$env:DMB_ACTION_HOST = "127.0.0.1"
$env:DMB_ACTION_PORT = "$Port"
$env:DMB_ACTION_API_KEY = $ApiKey

if ($Profile -eq "full") {
    $env:DMB_FULL_ACCESS_CONFIRMATION = "I UNDERSTAND THIS GRANTS FULL CONTROL"
    $admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $admin) {
        Write-Warning "Full mode is active, but this terminal is not elevated. Administrator-only operations will fail."
    }
}

Write-Host "Action Gateway starting on localhost:$Port with profile '$Profile'." -ForegroundColor Cyan
Write-Host "Expose it only through an authenticated HTTPS tunnel or reverse proxy." -ForegroundColor Yellow
& .\.venv\Scripts\python.exe -m desktop_mcp_bridge actions
