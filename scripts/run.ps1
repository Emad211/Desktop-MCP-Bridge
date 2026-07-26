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
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Virtual environment not found. Run .\scripts\install.ps1 first."
}

$roots = @()
foreach ($root in $AllowedRoot) {
    $roots += ((Resolve-Path $root).Path -replace '\\', '/')
}
$env:DMB_ALLOWED_ROOTS = ($roots | ConvertTo-Json -Compress)
$env:DMB_ACCESS_PROFILE = $Profile
$env:DMB_TRANSPORT = $Transport
$env:DMB_HOST = "127.0.0.1"
$env:DMB_PORT = "$Port"
Remove-Item Env:DMB_FULL_ACCESS_CONFIRMATION -ErrorAction SilentlyContinue

& .\.venv\Scripts\python.exe -m desktop_mcp_bridge mcp
