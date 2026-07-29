param(
    [switch]$Quick,
    [switch]$TestScreen,
    [switch]$TestNetwork
)

$ErrorActionPreference = "Continue"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    $PythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $PythonCommand) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $PythonCommand) { $PythonCommand = Get-Command py.exe -ErrorAction SilentlyContinue }
    if ($PythonCommand) { $Python = $PythonCommand.Source }
}
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$Results = [ordered]@{}
$Results.repo_root = $RepoRoot
$Results.windows = [Environment]::OSVersion.VersionString
$Results.caller_administrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$Results.python_executable = if ($Python -and (Test-Path $Python)) { $Python } else { $null }
$Results.python = if ($Results.python_executable) { (& $Python --version 2>&1 | Out-String).Trim() } else { "missing" }
$Results.port_8766_in_use = [bool](Get-NetTCPConnection -LocalPort 8766 -ErrorAction SilentlyContinue)
$Results.kill_switch_active = Test-Path (Join-Path $StateDir "STOP")
$Results.encrypted_key_present = Test-Path (Join-Path $StateDir "action-key.clixml")
$Results.gateway_autostart = [bool](Get-ScheduledTask -TaskName "Desktop MCP Bridge Action Gateway" -ErrorAction SilentlyContinue)
$Results.tunnel_autostart = [bool](Get-ScheduledTask -TaskName "Desktop MCP Bridge Tunnel Supervisor" -ErrorAction SilentlyContinue)
$Results.tesseract = $null
foreach ($Candidate in @(
    "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
    "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
    "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe"
)) {
    if ($Candidate -and (Test-Path $Candidate)) {
        $Results.tesseract = $Candidate
        break
    }
}
$Results.tessdata_dir = Join-Path $StateDir "tessdata"
$Results.ocr_eng = Test-Path (Join-Path $Results.tessdata_dir "eng.traineddata")
$Results.ocr_fas = Test-Path (Join-Path $Results.tessdata_dir "fas.traineddata")
$Results.playwright_browser_path = Join-Path $RepoRoot ".playwright-browsers"
$Results.playwright_browser_present = [bool](Get-ChildItem $Results.playwright_browser_path -ErrorAction SilentlyContinue)
$Results.browser_runtime = $null
$BrowserStatePath = Join-Path $StateDir "browser-runtime.json"
if (Test-Path $BrowserStatePath) {
    try { $Results.browser_runtime = Get-Content $BrowserStatePath -Raw | ConvertFrom-Json } catch {}
}
$Results.system_browsers = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { $_ -and (Test-Path $_) }
$Results.tunnel_state = $null
$TunnelStatePath = Join-Path $StateDir "tunnel.json"
if (Test-Path $TunnelStatePath) {
    try { $Results.tunnel_state = Get-Content $TunnelStatePath -Raw | ConvertFrom-Json } catch {}
}

if ($Results.python_executable) {
    $ImportOutput = @(& $Python -c "from desktop_mcp_bridge.config import BridgeSettings; from desktop_mcp_bridge.action_api import app; from desktop_mcp_bridge.server import mcp; s=app.openapi(); assert '/v1/act' in s['paths']; print('imports/openapi: ok')" 2>&1)
    $Results.imports_openapi = $LASTEXITCODE -eq 0
    $Results.imports_openapi_output = ($ImportOutput | Out-String).Trim()
    if ($TestScreen -and -not $Quick) {
        $ScreenOutput = @(& $Python -c "from pathlib import Path; from desktop_mcp_bridge.config import BridgeSettings; from desktop_mcp_bridge.runtime import DesktopBridge; b=DesktopBridge(BridgeSettings(allowed_roots=[Path.cwd()])); data,meta=b.observe_desktop_bytes(); print(meta); b.close(); assert len(data)>1000" 2>&1)
        $Results.screen_capture = $LASTEXITCODE -eq 0
        $Results.screen_capture_output = ($ScreenOutput | Out-String).Trim()
    }
}
if ($TestNetwork -and -not $Quick) {
    try {
        $Results.network_profile = & (Join-Path $PSScriptRoot "get-network-profile.ps1") | ConvertFrom-Json
    } catch {
        $Results.network_profile_error = $_.Exception.Message
    }
}
if ($Results.tunnel_state -and $Results.tunnel_state.url) {
    try {
        $PublicHealth = Invoke-RestMethod -Uri "$($Results.tunnel_state.url.TrimEnd('/'))/health" -TimeoutSec 8
        $Results.public_endpoint_healthy = $PublicHealth.ok -eq $true
    } catch {
        $Results.public_endpoint_healthy = $false
    }
}

$Results | ConvertTo-Json -Depth 20
if ($Results.python -eq "missing" -or $Results.imports_openapi -eq $false) { exit 1 }
if (-not $Quick -and -not $Results.tesseract) { exit 1 }
if (-not $Quick -and -not ($Results.playwright_browser_present -or $Results.system_browsers.Count -gt 0)) { exit 1 }
