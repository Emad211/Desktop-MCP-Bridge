param(
    [switch]$SkipBrowser,
    [switch]$SkipOCR,
    [switch]$SkipDevDependencies,
    [switch]$ForceRecreateVenv
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

function Ensure-WingetPackage {
    param([string[]]$Ids, [string]$DisplayName)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required to install $DisplayName automatically. Install it manually and retry."
    }
    foreach ($id in $Ids) {
        Write-Host "Trying to install $DisplayName ($id)..." -ForegroundColor Cyan
        & winget install --id $id --exact --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) { return }
    }
    throw "Unable to install $DisplayName using package IDs: $($Ids -join ', ')"
}

function Get-SystemChromiumBrowser {
    $Candidates = @(
        @{ Label = "msedge"; Path = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" },
        @{ Label = "msedge"; Path = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" },
        @{ Label = "chrome"; Path = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" },
        @{ Label = "chrome"; Path = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" },
        @{ Label = "chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe" }
    )
    foreach ($Candidate in $Candidates) {
        if ($Candidate.Path -and (Test-Path $Candidate.Path)) {
            return $Candidate
        }
    }
    return $null
}

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    Ensure-WingetPackage -Ids @("Python.Python.3.12", "Python.Python.3.11") -DisplayName "Python 3.11+"
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python launcher 'py' is still unavailable. Restart PowerShell and rerun this script."
}

$Version = & py -3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$Version -lt [version]"3.11") {
    throw "Python 3.11+ is required; found $Version"
}

if ($ForceRecreateVenv -and (Test-Path ".venv")) {
    Remove-Item ".venv" -Recurse -Force
}
if (-not (Test-Path ".venv")) {
    & py -3 -m venv .venv
}

$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
& $Python -m pip install --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) { throw "Unable to update pip/setuptools/wheel." }
if ($SkipDevDependencies) {
    & $Python -m pip install -e "."
} else {
    & $Python -m pip install -e ".[dev]"
}
if ($LASTEXITCODE -ne 0) { throw "Unable to install Desktop MCP Bridge dependencies." }

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$BrowserStatePath = Join-Path $StateDir "browser-runtime.json"
$BrowserPath = Join-Path $RepoRoot ".playwright-browsers"
$env:PLAYWRIGHT_BROWSERS_PATH = $BrowserPath
if (-not $SkipBrowser) {
    Write-Host "Installing the managed Chromium runtime..." -ForegroundColor Cyan
    & $Python -m playwright install chromium
    $PlaywrightExitCode = $LASTEXITCODE
    if ($PlaywrightExitCode -eq 0) {
        [ordered]@{
            mode = "playwright-managed"
            browser_path = $BrowserPath
            installed_at = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json | Set-Content $BrowserStatePath -Encoding UTF8
    } else {
        $Fallback = Get-SystemChromiumBrowser
        if (-not $Fallback) {
            throw "Playwright Chromium download failed with exit code $PlaywrightExitCode and no local Edge/Chrome fallback was found."
        }
        Write-Warning "Playwright Chromium download failed (exit $PlaywrightExitCode). The bridge will use local $($Fallback.Label): $($Fallback.Path)"
        [ordered]@{
            mode = "system-browser-fallback"
            channel = $Fallback.Label
            executable_path = $Fallback.Path
            playwright_download_exit_code = $PlaywrightExitCode
            detected_at = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json | Set-Content $BrowserStatePath -Encoding UTF8
    }
}

if (-not $SkipOCR) {
    $TesseractCandidates = @(
        "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
        "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
        "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    if (-not $TesseractCandidates) {
        Ensure-WingetPackage -Ids @("tesseract-ocr.tesseract", "UB-Mannheim.TesseractOCR") -DisplayName "Tesseract OCR"
    }
    & (Join-Path $PSScriptRoot "install-ocr-languages.ps1") -Languages @("eng", "fas") | Out-Null
}

Write-Host "Running installation diagnostics..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "diagnose.ps1") -Quick
if ($LASTEXITCODE -ne 0) { throw "Installation diagnostics failed." }

Write-Host ""
Write-Host "Desktop MCP Bridge v1.1 installation complete." -ForegroundColor Green
Write-Host "Next: .\scripts\repair-deployment.ps1 -FullAccess -Autonomous -IUnderstand" -ForegroundColor Yellow
