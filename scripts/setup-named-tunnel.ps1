param(
    [Parameter(Mandatory=$true)][string]$TunnelName,
    [Parameter(Mandatory=$true)][string]$Hostname,
    [int]$Port = 8766,
    [switch]$InstallIfMissing,
    [switch]$RunNow
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) { throw "cloudflared not found. Add -InstallIfMissing." }
    & winget install --id Cloudflare.cloudflared --exact --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    throw "cloudflared is still unavailable. Restart PowerShell and retry."
}

$CloudflaredDir = Join-Path $env:USERPROFILE ".cloudflared"
New-Item -ItemType Directory -Path $CloudflaredDir -Force | Out-Null
if (-not (Test-Path (Join-Path $CloudflaredDir "cert.pem"))) {
    Write-Host "A browser window will open for Cloudflare authorization." -ForegroundColor Cyan
    & cloudflared tunnel login
}

$Existing = (& cloudflared tunnel list --output json | ConvertFrom-Json) | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
if (-not $Existing) {
    & cloudflared tunnel create $TunnelName
    $Existing = (& cloudflared tunnel list --output json | ConvertFrom-Json) | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
}
if (-not $Existing) { throw "Unable to create or locate tunnel '$TunnelName'." }

$Credentials = Join-Path $CloudflaredDir ("{0}.json" -f $Existing.id)
$ConfigPath = Join-Path $CloudflaredDir ("desktop-mcp-{0}.yml" -f $TunnelName)
@"
tunnel: $($Existing.id)
credentials-file: $($Credentials -replace '\\','/')
ingress:
  - hostname: $Hostname
    service: http://127.0.0.1:$Port
  - service: http_status:404
"@ | Set-Content -Path $ConfigPath -Encoding UTF8

& cloudflared tunnel route dns $TunnelName $Hostname
Write-Host "Named tunnel configured: https://$Hostname" -ForegroundColor Green
Write-Host "Config: $ConfigPath"
Write-Host "Run: cloudflared tunnel --config `"$ConfigPath`" run $TunnelName" -ForegroundColor Cyan
if ($RunNow) { & cloudflared tunnel --config $ConfigPath run $TunnelName }
