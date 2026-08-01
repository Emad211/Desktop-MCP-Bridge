param(
    [int]$Port = 3006,
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant-proxy.json"),
    [int]$WaitSeconds = 15
)

$ErrorActionPreference = "Stop"
$State = $null
if (Test-Path $StatePath) {
    try { $State = Get-Content $StatePath -Raw | ConvertFrom-Json } catch {}
}

$Attempts = New-Object System.Collections.Generic.List[object]
function Stop-RecordedProcess {
    param(
        [int]$ProcessId,
        [string]$ExpectedStartedAt,
        [string]$Role
    )
    if (-not $ProcessId -or $ProcessId -eq $PID) { return }
    $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $Process) { return }
    $ActualStartedAt = $Process.StartTime.ToUniversalTime().ToString("o")
    if ($ExpectedStartedAt -and $ActualStartedAt -ne $ExpectedStartedAt) {
        $Attempts.Add([pscustomobject]@{
            role = $Role
            process_id = $ProcessId
            stopped = $false
            reason = "process-start-time-mismatch"
        })
        return
    }
    $Output = @(& taskkill.exe /PID $ProcessId /T /F 2>&1)
    $Attempts.Add([pscustomobject]@{
        role = $Role
        process_id = $ProcessId
        stopped = ($LASTEXITCODE -eq 0)
        exit_code = $LASTEXITCODE
        output = ($Output | Out-String).Trim()
    })
}

if ($State) {
    Stop-RecordedProcess `
        -ProcessId ([int]$State.launcher_pid) `
        -ExpectedStartedAt ([string]$State.launcher_started_at) `
        -Role "launcher"
    Stop-RecordedProcess `
        -ProcessId ([int]$State.listener_pid) `
        -ExpectedStartedAt ([string]$State.listener_started_at) `
        -Role "listener"
}

$Deadline = (Get-Date).AddSeconds([Math]::Max(1, $WaitSeconds))
do {
    Start-Sleep -Milliseconds 250
    $Listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $RecordedStillListening = $false
    if ($State -and $State.listener_pid) {
        $RecordedStillListening = @($Listeners | Where-Object {
            [int]$_.OwningProcess -eq [int]$State.listener_pid
        }).Count -gt 0
    }
    if (-not $RecordedStillListening) { break }
} while ((Get-Date) -lt $Deadline)

$Remaining = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$RemainingPids = @($Remaining | Select-Object -ExpandProperty OwningProcess -Unique)
$OwnedRemaining = @()
if ($State -and $State.listener_pid -and ($RemainingPids -contains [int]$State.listener_pid)) {
    $OwnedRemaining += [int]$State.listener_pid
}
if ($OwnedRemaining.Count -gt 0) {
    throw "The recorded SuperAssistant listener is still active on port $Port. PID: $($OwnedRemaining -join ', ')"
}

Remove-Item $StatePath -Force -ErrorAction SilentlyContinue
[ordered]@{
    stopped = $true
    state_path = $StatePath
    port = $Port
    attempts = @($Attempts.ToArray())
    remaining_listener_process_ids = $RemainingPids
    foreign_listeners_preserved = @($RemainingPids | Where-Object {
        -not $State -or -not $State.listener_pid -or [int]$_ -ne [int]$State.listener_pid
    })
} | ConvertTo-Json -Depth 10
