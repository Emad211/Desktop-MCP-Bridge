param(
    [int]$Port = 8766,
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "tunnel.json"

try {
    $LocalHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($LocalHealth.ok -ne $true) { throw "Local gateway health returned ok=false." }
} catch {
    throw "The local Action Gateway is not healthy on 127.0.0.1:$Port."
}

if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
        throw "Tailscale is not installed. Re-run with -InstallIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required for automatic Tailscale installation."
    }
    & winget install --id Tailscale.Tailscale --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "Tailscale installation failed: $LASTEXITCODE" }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
$Tailscale = (Get-Command tailscale -ErrorAction Stop).Source

if ($Restart) {
    & $Tailscale funnel --https=443 off | Out-Null
}

$Status = $null
try { $Status = (& $Tailscale status --json | ConvertFrom-Json) } catch {}
if (-not $Status -or $Status.BackendState -ne "Running") {
    if (-not $LoginIfNeeded) {
        throw "Tailscale is installed but not logged in. Run 'tailscale up' once, or rerun with -LoginIfNeeded."
    }
    Write-Host "Tailscale login/consent may open in a browser." -ForegroundColor Yellow
    & $Tailscale up
    if ($LASTEXITCODE -ne 0) {
        throw "tailscale up failed. V2Ray TUN mode or another VPN adapter may conflict with Tailscale; try V2Ray system-proxy mode or use ngrok. Exit code: $LASTEXITCODE"
    }
    $Status = (& $Tailscale status --json | ConvertFrom-Json)
}

$Output = & $Tailscale funnel --yes --bg --https=443 "http://127.0.0.1:$Port" 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Tailscale Funnel failed. Output: $($Output | Out-String)"
}
$Status = (& $Tailscale status --json | ConvertFrom-Json)
$DnsName = [string]$Status.Self.DNSName
$DnsName = $DnsName.Trim().TrimEnd('.')
if ([string]::IsNullOrWhiteSpace($DnsName)) {
    throw "Tailscale is running but no MagicDNS hostname was returned."
}
$Url = "https://$DnsName"
& (Join-Path $PSScriptRoot "test-public-endpoint.ps1") -PublicBaseUrl $Url | Out-Null

$State = [ordered]@{
    provider = "tailscale-funnel"
    url = $Url
    local_url = "http://127.0.0.1:$Port"
    healthy = $true
    persistent = $true
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    stop_command = "tailscale funnel --https=443 off"
}
$State | ConvertTo-Json -Depth 6 | Set-Content $StatePath -Encoding UTF8
$State | ConvertTo-Json -Depth 6
