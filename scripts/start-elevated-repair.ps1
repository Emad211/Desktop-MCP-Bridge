param(
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$InstallAutostart,
    [switch]$StartTunnel,
    [switch]$InstallTunnelAutostart,
    [ValidateSet("auto", "ngrok", "cloudflare", "tailscale")]
    [string]$TunnelProvider = "auto",
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$AllowEphemeral,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
if ($FullAccess -and -not $IUnderstand) {
    throw "Full access repair requires -IUnderstand."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$RepairRunId = [guid]::NewGuid().ToString()
$ProgressPath = Join-Path $StateDir "repair-progress.json"
$ReportPath = Join-Path $StateDir "repair-report.json"
$RequestPath = Join-Path $StateDir "repair-request-$RepairRunId.json"

$Request = [ordered]@{
    repair_run_id = $RepairRunId
    repo_root = $RepoRoot
    repair_script = Join-Path $PSScriptRoot "repair-deployment.ps1"
    progress_path = $ProgressPath
    report_path = $ReportPath
    fullAccess = [bool]$FullAccess
    autonomous = [bool]$Autonomous
    installAutostart = [bool]$InstallAutostart
    startTunnel = [bool]$StartTunnel
    installTunnelAutostart = [bool]$InstallTunnelAutostart
    installIfMissing = [bool]$InstallIfMissing
    loginIfNeeded = [bool]$LoginIfNeeded
    allowEphemeral = [bool]$AllowEphemeral
    iUnderstand = [bool]$IUnderstand
    tunnel_provider = $TunnelProvider
    network_mode = $NetworkMode
    created_at = (Get-Date).ToUniversalTime().ToString("o")
}
$Request | ConvertTo-Json -Depth 10 | Set-Content -Path $RequestPath -Encoding UTF8

[ordered]@{
    repair_run_id = $RepairRunId
    status = "broker_starting"
    step = "elevation"
    message = "An elevation broker is starting. Approve the Windows UAC prompt when it appears."
    request_path = $RequestPath
    progress_path = $ProgressPath
    report_path = $ReportPath
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 10 | Set-Content -Path $ProgressPath -Encoding UTF8

$BrokerScript = Join-Path $PSScriptRoot "elevation-broker.ps1"
$Broker = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", ('"{0}"' -f $BrokerScript),
        "-RequestPath", ('"{0}"' -f $RequestPath)
    ) `
    -WorkingDirectory $RepoRoot `
    -WindowStyle Hidden `
    -PassThru

[ordered]@{
    launched = $true
    uac_required = $true
    repair_run_id = $RepairRunId
    broker_pid = $Broker.Id
    progress_path = $ProgressPath
    report_path = $ReportPath
    poll_command = ".\scripts\repair-status.ps1 -RepairRunId $RepairRunId"
    message = "The command returned immediately. Approve the UAC prompt, then poll repair-status.ps1."
} | ConvertTo-Json -Depth 10
