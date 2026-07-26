param(
    [Parameter(Mandatory=$true)]
    [string[]]$AllowedRoot,
    [ValidateSet("safe", "developer")]
    [string]$Profile = "safe",
    [ValidateSet("stdio", "streamable-http", "sse")]
    [string]$Transport = "stdio",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}

$Roots = @()
foreach ($Root in $AllowedRoot) {
    $Roots += ((Resolve-Path $Root).Path -replace '\\', '/')
}
$env:DMB_ALLOWED_ROOTS = ($Roots | ConvertTo-Json -Compress)
$env:DMB_ACCESS_PROFILE = $Profile
$env:DMB_TRANSPORT = $Transport
$env:DMB_HOST = "127.0.0.1"
$env:DMB_PORT = "$Port"
$env:PLAYWRIGHT_BROWSERS_PATH = (Join-Path $RepoRoot ".playwright-browsers")
$env:DMB_TESSDATA_DIR = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tessdata")
Remove-Item Env:DMB_FULL_ACCESS_CONFIRMATION -ErrorAction SilentlyContinue

& .\.venv\Scripts\python.exe -m desktop_mcp_bridge mcp
