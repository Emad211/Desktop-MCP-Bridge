param([switch]$Quick, [switch]$TestScreen)

$ErrorActionPreference = "Continue"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
$Results = [ordered]@{}
$Results.repo_root = $RepoRoot
$Results.windows = [Environment]::OSVersion.VersionString
$Results.administrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$Results.python = if (Test-Path $Python) { (& $Python --version 2>&1 | Out-String).Trim() } else { "missing" }
$Results.port_8766_in_use = [bool](Get-NetTCPConnection -LocalPort 8766 -ErrorAction SilentlyContinue)
$Results.kill_switch_active = Test-Path (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\STOP")
$Results.encrypted_key_present = Test-Path (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml")
$Results.tesseract = $null
foreach ($Candidate in @("$env:ProgramFiles\Tesseract-OCR\tesseract.exe", "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe", "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe")) {
    if ($Candidate -and (Test-Path $Candidate)) { $Results.tesseract = $Candidate; break }
}
$Results.playwright_browser_path = Join-Path $RepoRoot ".playwright-browsers"
$Results.playwright_browser_present = Test-Path $Results.playwright_browser_path

if (Test-Path $Python) {
    & $Python -c "from desktop_mcp_bridge.config import BridgeSettings; from desktop_mcp_bridge.action_api import app; from desktop_mcp_bridge.server import mcp; s=app.openapi(); assert '/v1/act' in s['paths']; print('imports/openapi: ok')"
    $Results.imports_openapi = $LASTEXITCODE -eq 0
    if ($TestScreen -and -not $Quick) {
        & $Python -c "from pathlib import Path; from desktop_mcp_bridge.config import BridgeSettings; from desktop_mcp_bridge.runtime import DesktopBridge; b=DesktopBridge(BridgeSettings(allowed_roots=[Path.cwd()])); data,meta=b.observe_desktop_bytes(); print(meta); b.close(); assert len(data)>1000"
        $Results.screen_capture = $LASTEXITCODE -eq 0
    }
}

$Results | ConvertTo-Json -Depth 5
if ($Results.python -eq "missing" -or $Results.imports_openapi -eq $false) { exit 1 }
