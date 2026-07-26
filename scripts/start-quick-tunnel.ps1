param(
    [int]$Port = 8766,
    [switch]$InstallIfMissing,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "quick-tunnel.json"
$OutLog = Join-Path $StateDir "quick-tunnel.stdout.log"
$ErrLog = Join-Path $StateDir "quick-tunnel.stderr.log"

if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-quick-tunnel.ps1") -ErrorAction SilentlyContinue
}
if (Test-Path $StatePath) {
    try {
        $Existing = Get-Content $StatePath -Raw | ConvertFrom-Json
        if (Get-Process -Id $Existing.pid -ErrorAction SilentlyContinue) {
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
Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
$Process = Start-Process -FilePath $Cloudflared `
    -ArgumentList @("tunnel", "--url", "http://127.0.0.1:$Port", "--no-autoupdate") `
    -WindowStyle Minimized `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -PassThru

$Deadline = (Get-Date).AddSeconds(60)
$Url = $null
do {
    Start-Sleep -Milliseconds 500
    $Text = ""
    if (Test-Path $OutLog) { $Text += (Get-Content $OutLog -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $ErrLog) { $Text += "`n" + (Get-Content $ErrLog -Raw -ErrorAction SilentlyContinue) }
    $Match = [regex]::Match($Text, 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
    if ($Match.Success) { $Url = $Match.Value; break }
    if ($Process.HasExited) {
        throw "cloudflared exited before producing a URL. Inspect $ErrLog"
    }
} while ((Get-Date) -lt $Deadline)

if (-not $Url) {
    try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
    throw "No Quick Tunnel URL was produced within 60 seconds. Inspect $ErrLog"
}
$State = [ordered]@{
    pid = $Process.Id
    url = $Url
    local_url = "http://127.0.0.1:$Port"
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    stdout_log = $OutLog
    stderr_log = $ErrLog
}
$State | ConvertTo-Json | Set-Content -Path $StatePath -Encoding UTF8
$State | ConvertTo-Json -Depth 5
