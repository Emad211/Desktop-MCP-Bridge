param(
    [ValidateSet("stdio", "streamable-http", "sse")]
    [string]$Transport = "stdio",
    [int]$Port = 8765,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot
if (-not $IUnderstand) { throw "Full MCP access requires -IUnderstand." }
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}

$env:DMB_ACCESS_PROFILE = "full"
$env:DMB_FULL_ACCESS_CONFIRMATION = "I UNDERSTAND THIS GRANTS FULL CONTROL"
$env:DMB_ALLOWED_ROOTS = '["C:/"]'
$env:DMB_TRANSPORT = $Transport
$env:DMB_HOST = "127.0.0.1"
$env:DMB_PORT = "$Port"

& (Join-Path $PSScriptRoot "set-runtime-environment.ps1") -RepoRoot $RepoRoot

$Admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $Admin) {
    Write-Warning "This process is not elevated. Relaunch PowerShell as Administrator for OS-wide actions."
}

& .\.venv\Scripts\python.exe -m desktop_mcp_bridge mcp
