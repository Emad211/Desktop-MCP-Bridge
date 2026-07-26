$ErrorActionPreference = "Stop"

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python 3.11+ is required. Install it from python.org and enable the py launcher."
}

$Version = & py -3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$Version -lt [version]"3.11") {
    throw "Python 3.11+ is required; found $Version"
}

if (-not (Test-Path ".venv")) {
    & py -3 -m venv .venv
}

& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -e ".[dev]"

Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Run .\scripts\run.ps1 -AllowedRoot 'C:\path\to\workspace'"
