param(
    [int]$Port = 8766,
    [switch]$InstallIfMissing
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
        throw "cloudflared was not found. Install it, or rerun with -InstallIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required for automatic cloudflared installation."
    }
    & winget install --id Cloudflare.cloudflared --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "cloudflared installation failed with exit code $LASTEXITCODE"
    }
}

Write-Warning "Quick Tunnels are temporary and intended only for testing. The URL changes on restart."
Write-Host "Forwarding HTTPS to http://127.0.0.1:$Port" -ForegroundColor Cyan
& cloudflared tunnel --url "http://127.0.0.1:$Port"
