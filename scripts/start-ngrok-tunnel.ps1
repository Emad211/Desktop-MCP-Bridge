param(
    [int]$Port = 8766,
    [string]$AuthToken = $env:NGROK_AUTHTOKEN,
    [string]$ProxyUrl = "",
    [switch]$InstallIfMissing,
    [switch]$Restart,
    [int]$ApiPort = 4040
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "tunnel.json"
$OutLog = Join-Path $StateDir "ngrok.stdout.log"
$ErrLog = Join-Path $StateDir "ngrok.stderr.log"

try {
    $LocalHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($LocalHealth.ok -ne $true) { throw "Local gateway health returned ok=false." }
} catch {
    throw "The local Action Gateway is not healthy on 127.0.0.1:$Port."
}

if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
        throw "ngrok is not installed. Re-run with -InstallIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required for automatic ngrok installation."
    }
    & winget install --id Ngrok.Ngrok --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "ngrok installation failed: $LASTEXITCODE" }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
$Ngrok = (Get-Command ngrok -ErrorAction Stop).Source

if ($AuthToken) {
    & $Ngrok config add-authtoken $AuthToken | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ngrok rejected the supplied authtoken." }
}

if ($Restart) {
    $Existing = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $ApiPort -State Listen -ErrorAction SilentlyContinue
    foreach ($Connection in $Existing) {
        & taskkill.exe /PID $Connection.OwningProcess /T /F | Out-Null
    }
}

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
    $Process = Start-Process -FilePath $Ngrok `
        -ArgumentList @("http", "http://127.0.0.1:$Port", "--log=stdout", "--log-format=json") `
        -WindowStyle Minimized `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru
} finally {
    foreach ($Name in $PreviousProxyEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $PreviousProxyEnvironment[$Name], "Process")
    }
}

$Deadline = (Get-Date).AddSeconds(60)
$Url = $null
do {
    Start-Sleep -Milliseconds 500
    try {
        $Tunnels = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/api/tunnels" -TimeoutSec 3
        $HttpsTunnel = $Tunnels.tunnels | Where-Object { $_.public_url -like "https://*" } | Select-Object -First 1
        if ($HttpsTunnel) { $Url = [string]$HttpsTunnel.public_url; break }
    } catch {}
    if ($Process.HasExited) {
        $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "ngrok exited before creating an endpoint. $ErrorText"
    }
} while ((Get-Date) -lt $Deadline)

if (-not $Url) {
    try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
    throw "ngrok did not create an HTTPS endpoint within 60 seconds. Run 'ngrok diagnose' and verify the authtoken."
}
& (Join-Path $PSScriptRoot "test-public-endpoint.ps1") -PublicBaseUrl $Url | Out-Null

$State = [ordered]@{
    provider = "ngrok"
    pid = $Process.Id
    url = $Url
    local_url = "http://127.0.0.1:$Port"
    proxy_url = $(if ($ProxyUrl) { $ProxyUrl } else { $null })
    healthy = $true
    persistent = $false
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    stdout_log = $OutLog
    stderr_log = $ErrLog
}
$State | ConvertTo-Json -Depth 6 | Set-Content $StatePath -Encoding UTF8
$State | ConvertTo-Json -Depth 6
