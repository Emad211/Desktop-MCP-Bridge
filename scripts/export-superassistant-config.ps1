param(
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "full",
    [string[]]$AllowedRoot = @("C:\"),
    [string]$ServerName = "desktop-mcp-bridge",
    [string]$OutputPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant\config.json"),
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "Project Python was not found at $Python. Run scripts/install.ps1 first."
}
if ($Profile -eq "full" -and -not $IUnderstand) {
    throw "Full SuperAssistant access requires -IUnderstand."
}
if ([string]::IsNullOrWhiteSpace($ServerName)) {
    throw "ServerName cannot be empty."
}

$Roots = @()
foreach ($Root in $AllowedRoot) {
    if ([string]::IsNullOrWhiteSpace($Root)) { continue }
    $Resolved = (Resolve-Path $Root).Path -replace '\\', '/'
    $Roots += $Resolved
}
if ($Roots.Count -eq 0) {
    throw "At least one existing AllowedRoot is required."
}

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$TessdataDir = Join-Path $StateDir "tessdata"
$Environment = [ordered]@{
    DMB_TRANSPORT = "stdio"
    DMB_HOST = "127.0.0.1"
    DMB_PORT = "8765"
    DMB_ACCESS_PROFILE = $Profile
    DMB_ALLOWED_ROOTS = (ConvertTo-Json -InputObject @($Roots) -Compress)
    DMB_APPROVAL_POLICY = "guarded"
    PLAYWRIGHT_BROWSERS_PATH = (Join-Path $RepoRoot ".playwright-browsers")
    DMB_TESSDATA_DIR = $TessdataDir
    TESSDATA_PREFIX = ($TessdataDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
}
if ($Profile -eq "full") {
    $Environment.DMB_FULL_ACCESS_CONFIRMATION = "I UNDERSTAND THIS GRANTS FULL CONTROL"
}

$BrowserStatePath = Join-Path $StateDir "browser-runtime.json"
if (Test-Path $BrowserStatePath) {
    try {
        $BrowserState = Get-Content $BrowserStatePath -Raw | ConvertFrom-Json
        if ($BrowserState.channel) {
            $Environment.DMB_BROWSER_CHANNEL = [string]$BrowserState.channel
        }
        if ($BrowserState.executable_path -and (Test-Path $BrowserState.executable_path)) {
            $Environment.DMB_BROWSER_EXECUTABLE_PATH = [string]$BrowserState.executable_path
        }
    } catch {
        throw "Unable to read browser runtime state: $($_.Exception.Message)"
    }
}

$TesseractCandidates = @(
    "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
    "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
    "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe"
) | Where-Object { $_ -and (Test-Path $_) }
if ($TesseractCandidates) {
    $Environment.DMB_TESSERACT_COMMAND = [string]$TesseractCandidates[0]
}

$Server = [ordered]@{
    command = $Python
    args = @("-m", "desktop_mcp_bridge.superassistant_server")
    env = $Environment
}
$Config = [ordered]@{
    mcpServers = [ordered]@{
        $ServerName = $Server
    }
}

$OutputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$Config | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

$RoundTrip = Get-Content $OutputPath -Raw | ConvertFrom-Json
if (-not $RoundTrip.mcpServers.$ServerName) {
    throw "Generated config failed JSON round-trip validation."
}

[ordered]@{
    ok = $true
    config_path = $OutputPath
    server_name = $ServerName
    command = $Python
    module = "desktop_mcp_bridge.superassistant_server"
    profile = $Profile
    allowed_roots = $Roots
    contains_secrets = $false
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 10
