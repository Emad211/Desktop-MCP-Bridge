param(
    [Parameter(Mandatory=$true)]
    [string]$AllowedRoot,
    [ValidateSet("stdio", "streamable-http", "sse")]
    [string]$Transport = "stdio",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$ResolvedRoot = (Resolve-Path $AllowedRoot).Path
$env:DMB_ALLOWED_ROOTS = '["' + ($ResolvedRoot -replace '\\', '/') + '"]'
$env:DMB_TRANSPORT = $Transport
$env:DMB_HOST = "127.0.0.1"
$env:DMB_PORT = "$Port"
$env:DMB_ENABLE_DELETE = "false"
$env:DMB_ENABLE_PROCESS_CONTROL = "false"

& .\.venv\Scripts\desktop-mcp-bridge.exe
