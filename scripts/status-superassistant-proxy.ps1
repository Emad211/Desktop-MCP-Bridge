param(
    [int]$Port = 3006,
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant-proxy.json"),
    [int]$LogTailLines = 80
)

$ErrorActionPreference = "Stop"
$State = $null
if (Test-Path $StatePath) {
    try { $State = Get-Content $StatePath -Raw | ConvertFrom-Json } catch {}
}

$Listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$ListenerPids = @($Listeners | Select-Object -ExpandProperty OwningProcess -Unique)
$RecordedListenerRunning = $false
$RecordedListenerIdentityMatches = $false
$RecordedLauncherRunning = $false

if ($State -and $State.launcher_pid) {
    $RecordedLauncherRunning = [bool](Get-Process -Id ([int]$State.launcher_pid) -ErrorAction SilentlyContinue)
}
if ($State -and $State.listener_pid) {
    $Recorded = Get-Process -Id ([int]$State.listener_pid) -ErrorAction SilentlyContinue
    $RecordedListenerRunning = [bool]$Recorded
    if ($Recorded) {
        $ActualStartedAt = $Recorded.StartTime.ToUniversalTime().ToString("o")
        $RecordedListenerIdentityMatches = (
            $ListenerPids -contains [int]$State.listener_pid -and
            (
                -not $State.listener_started_at -or
                $ActualStartedAt -eq [string]$State.listener_started_at
            )
        )
    }
}

$ForeignListenerPids = @()
foreach ($ListenerPid in $ListenerPids) {
    if (-not $State -or -not $State.listener_pid -or [int]$ListenerPid -ne [int]$State.listener_pid) {
        $ForeignListenerPids += [int]$ListenerPid
    }
}

$StdoutTail = ""
$StderrTail = ""
if ($State -and $State.stdout_log -and (Test-Path $State.stdout_log)) {
    $StdoutTail = (Get-Content $State.stdout_log -Tail $LogTailLines | Out-String).Trim()
}
if ($State -and $State.stderr_log -and (Test-Path $State.stderr_log)) {
    $StderrTail = (Get-Content $State.stderr_log -Tail $LogTailLines | Out-String).Trim()
}
$CombinedLog = ($StdoutTail + "`n" + $StderrTail).Trim()
$BridgeConnected = $CombinedLog -match "(?im)Connected servers:\s*.*desktop-mcp-bridge" -or (
    $CombinedLog -match "(?im)Connected to\s+1\s+of\s+1\s+servers" -and
    $CombinedLog -notmatch "(?im)Failed to connect to servers:\s*.*desktop-mcp-bridge"
)
$BridgeConnectionFailed = $CombinedLog -match "(?im)Failed to connect to servers:\s*.*desktop-mcp-bridge"

[ordered]@{
    state_found = [bool]$State
    state_path = $StatePath
    port = $Port
    endpoint = if ($State) { $State.endpoint } else { $null }
    output_transport = if ($State) { $State.output_transport } else { $null }
    config_path = if ($State) { $State.config_path } else { $null }
    launcher_pid = if ($State) { $State.launcher_pid } else { $null }
    launcher_running = $RecordedLauncherRunning
    listener_pid = if ($State) { $State.listener_pid } else { $null }
    listener_running = $RecordedListenerRunning
    listener_identity_matches = $RecordedListenerIdentityMatches
    listener_process_ids = $ListenerPids
    foreign_listener_process_ids = $ForeignListenerPids
    owned_listener_healthy = [bool]($RecordedListenerIdentityMatches -and $BridgeConnected -and -not $BridgeConnectionFailed)
    bridge_connected = [bool]$BridgeConnected
    bridge_connection_failed = [bool]$BridgeConnectionFailed
    stdout_log = if ($State) { $State.stdout_log } else { $null }
    stderr_log = if ($State) { $State.stderr_log } else { $null }
    stdout_tail = $StdoutTail
    stderr_tail = $StderrTail
} | ConvertTo-Json -Depth 10
