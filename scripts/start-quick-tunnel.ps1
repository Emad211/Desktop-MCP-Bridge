param(
    [int]$Port = 8766,
    [string]$ProxyUrl = "",
    [switch]$InstallIfMissing,
    [switch]$Restart,
    [int]$StartupTimeoutSeconds = 75
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "quick-tunnel.json"
$UnifiedStatePath = Join-Path $StateDir "tunnel.json"
$OutLog = Join-Path $StateDir "quick-tunnel.stdout.log"
$ErrLog = Join-Path $StateDir "quick-tunnel.stderr.log"

function Test-PublicHealth {
    param([string]$Url, [int]$Attempts = 20)
    for ($Index = 0; $Index -lt $Attempts; $Index++) {
        try {
            $Response = Invoke-RestMethod -Uri "$($Url.TrimEnd('/'))/health" -TimeoutSec 5
            if ($Response.ok -eq $true) { return $true }
        } catch {}
        Start-Sleep -Seconds 1
    }
    return $false
}

try {
    $LocalHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($LocalHealth.ok -ne $true) { throw "Local gateway health returned ok=false." }
} catch {
    throw "The local Action Gateway is not healthy on 127.0.0.1:$Port. Start it before creating a tunnel."
}

if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-quick-tunnel.ps1") -ErrorAction SilentlyContinue
}
if (Test-Path $StatePath) {
    try {
        $Existing = Get-Content $StatePath -Raw | ConvertFrom-Json
        if ((Get-Process -Id $Existing.pid -ErrorAction SilentlyContinue) -and (Test-PublicHealth $Existing.url 2)) {
            $Existing | ConvertTo-Json -Depth 5
            exit 0
        }
    } catch {}
}

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
        throw "cloudflared was not found. Re-run with -InstallIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required for automatic cloudflared installation."
    }
    & winget install --id Cloudflare.cloudflared --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "cloudflared installation failed: $LASTEXITCODE" }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
$Cloudflared = (Get-Command cloudflared -ErrorAction Stop).Source

$PreviousProxyEnvironment = @{}
foreach ($Name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
    $PreviousProxyEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($ProxyUrl) {
        [Environment]::SetEnvironmentVariable($Name, $ProxyUrl, "Process")
    } else {
        [Environment]::SetEnvironmentVariable($Name, $null, "Process")
    }
}
try {
    Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
    $Process = Start-Process -FilePath $Cloudflared `
        -ArgumentList @("tunnel", "--url", "http://127.0.0.1:$Port", "--no-autoupdate") `
        -WindowStyle Minimized `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru
} finally {
    foreach ($Name in $PreviousProxyEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $PreviousProxyEnvironment[$Name], "Process")
    }
}

$Deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
$Url = $null
do {
    Start-Sleep -Milliseconds 500
    $Text = ""
    if (Test-Path $OutLog) { $Text += (Get-Content $OutLog -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $ErrLog) { $Text += "`n" + (Get-Content $ErrLog -Raw -ErrorAction SilentlyContinue) }
    $Matches = [regex]::Matches($Text, 'https://(?<host>[a-zA-Z0-9][a-zA-Z0-9-]{5,})\.trycloudflare\.com')
    foreach ($Match in $Matches) {
        if ($Match.Groups['host'].Value -notin @('api', 'www')) {
            $Url = $Match.Value
            break
        }
    }
    if ($Url) { break }
    if ($Process.HasExited) {
        $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "cloudflared exited before producing a tunnel URL. $ErrorText"
    }
} while ((Get-Date) -lt $Deadline)

if (-not $Url) {
    try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
    $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
    throw "No valid random trycloudflare.com URL was produced. api.trycloudflare.com is not a tunnel URL. $ErrorText"
}
if (-not (Test-PublicHealth $Url)) {
    try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
    $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
    throw "Cloudflare produced $Url but the public /health endpoint was unreachable. The network may block api.trycloudflare.com or Cloudflare Tunnel edge connectivity. $ErrorText"
}

$State = [ordered]@{
    provider = "cloudflare-quick"
    pid = $Process.Id
    url = $Url
    local_url = "http://127.0.0.1:$Port"
    proxy_url = $(if ($ProxyUrl) { $ProxyUrl } else { $null })
    healthy = $true
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    stdout_log = $OutLog
    stderr_log = $ErrLog
}
$Json = $State | ConvertTo-Json -Depth 5
$Json | Set-Content -Path $StatePath -Encoding UTF8
$Json | Set-Content -Path $UnifiedStatePath -Encoding UTF8
$Json
