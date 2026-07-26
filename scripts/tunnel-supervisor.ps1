param(
    [ValidateSet("auto", "ngrok", "cloudflare", "tailscale")]
    [string]$Provider = "auto",
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [int]$Port = 8766,
    [int]$CheckIntervalSeconds = 20,
    [int]$FailureThreshold = 2,
    [string]$NgrokAuthToken = $env:NGROK_AUTHTOKEN,
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$AllowEphemeral
)

$ErrorActionPreference = "Continue"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$SupervisorStatePath = Join-Path $StateDir "tunnel-supervisor.json"
$TunnelStatePath = Join-Path $StateDir "tunnel.json"
$StopPath = Join-Path $StateDir "TUNNEL_STOP"
$EndpointChangePath = Join-Path $StateDir "endpoint-change.json"
$LogPath = Join-Path $StateDir "tunnel-supervisor.log"
Remove-Item $StopPath -Force -ErrorAction SilentlyContinue

function Write-SupervisorLog {
    param([string]$Message, [string]$Level = "INFO")
    $Line = "$(Get-Date -Format o) [$Level] $Message"
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
    Write-Host $Line
}

function Test-TunnelHealth {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        $Health = Invoke-RestMethod -Uri "$($Url.TrimEnd('/'))/health" -TimeoutSec 8
        return $Health.ok -eq $true
    } catch {
        return $false
    }
}

$SupervisorState = [ordered]@{
    pid = $PID
    provider = $Provider
    network_mode = $NetworkMode
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    log_path = $LogPath
    stop_path = $StopPath
    status = "running"
}
$SupervisorState | ConvertTo-Json | Set-Content $SupervisorStatePath -Encoding UTF8
Write-SupervisorLog "Tunnel supervisor started. PID=$PID Provider=$Provider NetworkMode=$NetworkMode"

$Failures = 0
$PreviousUrl = $null
while (-not (Test-Path $StopPath)) {
    $Tunnel = $null
    if (Test-Path $TunnelStatePath) {
        try { $Tunnel = Get-Content $TunnelStatePath -Raw | ConvertFrom-Json } catch {}
    }

    if ($Tunnel -and (Test-TunnelHealth $Tunnel.url)) {
        $Failures = 0
        if ($PreviousUrl -and $PreviousUrl -ne $Tunnel.url) {
            [ordered]@{
                previous_url = $PreviousUrl
                current_url = $Tunnel.url
                requires_gpt_update = -not [bool]$Tunnel.stable_url
                changed_at = (Get-Date).ToUniversalTime().ToString("o")
            } | ConvertTo-Json | Set-Content $EndpointChangePath -Encoding UTF8
            Write-SupervisorLog "Public endpoint changed from $PreviousUrl to $($Tunnel.url)." "WARN"
        }
        $PreviousUrl = [string]$Tunnel.url
        Start-Sleep -Seconds ([Math]::Max(5, $CheckIntervalSeconds))
        continue
    }

    $Failures++
    Write-SupervisorLog "Tunnel health failure $Failures/$FailureThreshold." "WARN"
    if ($Failures -lt [Math]::Max(1, $FailureThreshold)) {
        Start-Sleep -Seconds 5
        continue
    }

    & (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
    try {
        $Arguments = @{
            Provider = $Provider
            NetworkMode = $NetworkMode
            Port = $Port
            InstallIfMissing = $InstallIfMissing
            LoginIfNeeded = $LoginIfNeeded
            Restart = $true
        }
        if ($NgrokAuthToken) { $Arguments.NgrokAuthToken = $NgrokAuthToken }
        $Started = & (Join-Path $PSScriptRoot "start-tunnel.ps1") @Arguments | ConvertFrom-Json
        if (-not $AllowEphemeral -and -not [bool]$Started.stable_url) {
            & (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
            throw "Only an ephemeral URL was available. Configure ngrok or Tailscale, or start the supervisor with -AllowEphemeral."
        }
        $Failures = 0
        Write-SupervisorLog "Tunnel recovered through provider=$($Started.provider), route=$($Started.network_mode), url=$($Started.url)."
    } catch {
        Write-SupervisorLog "Tunnel recovery failed: $($_.Exception.Message)" "ERROR"
        Start-Sleep -Seconds 15
    }
}

$SupervisorState.status = "stopped"
$SupervisorState.stopped_at = (Get-Date).ToUniversalTime().ToString("o")
$SupervisorState | ConvertTo-Json | Set-Content $SupervisorStatePath -Encoding UTF8
Write-SupervisorLog "Tunnel supervisor stopped."
