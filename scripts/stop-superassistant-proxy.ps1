param(
    [int]$Port = 3006,
    [string]$StatePath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant-proxy.json"),
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Stop"
$State = $null
if (Test-Path $StatePath) {
    try { $State = Get-Content $StatePath -Raw | ConvertFrom-Json } catch {}
}

$Attempts = New-Object System.Collections.Generic.List[object]

function Get-ProcessStartTime {
    param([int]$ProcessId)
    $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $Process) { return $null }
    try { return $Process.StartTime.ToUniversalTime() } catch { return $null }
}

function Test-ProcessOwnsPort {
    param([int]$ProcessId)
    $Rows = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Where-Object { [int]$_.OwningProcess -eq $ProcessId })
    return $Rows.Count -gt 0
}

function Test-ExpectedIdentity {
    param([int]$ProcessId, [string[]]$ExpectedStartedAt)
    $Actual = Get-ProcessStartTime -ProcessId $ProcessId
    if (-not $Actual) { return $false }
    $Expected = @($ExpectedStartedAt | Where-Object { $_ })
    if ($Expected.Count -eq 0) { return $true }

    foreach ($Text in $Expected) {
        try {
            $Parsed = [datetimeoffset]::Parse([string]$Text).UtcDateTime
            if ([Math]::Abs(($Actual - $Parsed).TotalSeconds) -le 2) {
                return $true
            }
        } catch {}
    }

    # Process.StartTime precision is not stable across all Windows APIs/runners.
    # A recorded PID that is currently the sole owner of the configured localhost
    # listener is stronger evidence than an exact sub-second timestamp comparison.
    if (Test-ProcessOwnsPort -ProcessId $ProcessId) {
        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($Process -and $Process.ProcessName -eq "node") { return $true }
    }
    return $false
}

function Add-StopAttempt {
    param(
        [string]$Method,
        [int]$ProcessId,
        [string]$Role,
        [bool]$Succeeded,
        [int]$ExitCode = 0,
        [string]$Output = ""
    )
    $Attempts.Add([pscustomobject]@{
        method = $Method
        role = $Role
        process_id = $ProcessId
        succeeded = $Succeeded
        exit_code = $ExitCode
        output = $Output
    })
}

function Stop-OwnedProcessTree {
    param(
        [int]$ProcessId,
        [string[]]$ExpectedStartedAt,
        [string]$Role
    )
    if (-not $ProcessId -or $ProcessId -eq $PID) { return }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }
    if (-not (Test-ExpectedIdentity -ProcessId $ProcessId -ExpectedStartedAt $ExpectedStartedAt)) {
        Add-StopAttempt `
            -Method "identity-check" `
            -ProcessId $ProcessId `
            -Role $Role `
            -Succeeded $false `
            -Output "process-identity-mismatch-and-not-port-owner"
        return
    }

    $TaskkillOutput = @(& taskkill.exe /PID $ProcessId /T /F 2>&1)
    $TaskkillExit = $LASTEXITCODE
    Add-StopAttempt `
        -Method "taskkill-tree-force" `
        -ProcessId $ProcessId `
        -Role $Role `
        -Succeeded ($TaskkillExit -eq 0) `
        -ExitCode $TaskkillExit `
        -Output (($TaskkillOutput | Out-String).Trim())

    try { Wait-Process -Id $ProcessId -Timeout 8 -ErrorAction SilentlyContinue } catch {}
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Add-StopAttempt -Method "stop-process-force" -ProcessId $ProcessId -Role $Role -Succeeded $true
    } catch {
        Add-StopAttempt `
            -Method "stop-process-force" `
            -ProcessId $ProcessId `
            -Role $Role `
            -Succeeded $false `
            -Output $_.Exception.Message
    }
    try { Wait-Process -Id $ProcessId -Timeout 5 -ErrorAction SilentlyContinue } catch {}
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }

    try {
        $CimProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        $Termination = Invoke-CimMethod -InputObject $CimProcess -MethodName Terminate -ErrorAction Stop
        Add-StopAttempt `
            -Method "cim-terminate" `
            -ProcessId $ProcessId `
            -Role $Role `
            -Succeeded ($Termination.ReturnValue -eq 0) `
            -ExitCode ([int]$Termination.ReturnValue)
    } catch {
        Add-StopAttempt `
            -Method "cim-terminate" `
            -ProcessId $ProcessId `
            -Role $Role `
            -Succeeded $false `
            -Output $_.Exception.Message
    }
}

if ($State) {
    $TargetRows = New-Object System.Collections.Generic.List[object]
    if ($State.listener_pid) {
        $TargetRows.Add([pscustomobject]@{
            process_id = [int]$State.listener_pid
            role = "listener"
            expected_started_at = [string]$State.listener_started_at
        })
    }
    if ($State.launcher_pid) {
        $TargetRows.Add([pscustomobject]@{
            process_id = [int]$State.launcher_pid
            role = "launcher"
            expected_started_at = [string]$State.launcher_started_at
        })
    }

    foreach ($Group in @($TargetRows | Group-Object process_id)) {
        $ProcessId = [int]$Group.Name
        $Roles = @($Group.Group | Select-Object -ExpandProperty role -Unique)
        $Expected = @($Group.Group | Select-Object -ExpandProperty expected_started_at -Unique)
        Stop-OwnedProcessTree `
            -ProcessId $ProcessId `
            -ExpectedStartedAt $Expected `
            -Role ($Roles -join "+")
    }
}

$Deadline = (Get-Date).AddSeconds([Math]::Max(1, $WaitSeconds))
do {
    Start-Sleep -Milliseconds 250
    $Listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $OwnedListeners = @()
    foreach ($Listener in $Listeners) {
        $ListenerPid = [int]$Listener.OwningProcess
        $RecordedPids = @()
        if ($State -and $State.listener_pid) { $RecordedPids += [int]$State.listener_pid }
        if ($State -and $State.launcher_pid) { $RecordedPids += [int]$State.launcher_pid }
        if ($RecordedPids -contains $ListenerPid) { $OwnedListeners += $ListenerPid }
    }
    if ($OwnedListeners.Count -eq 0) { break }
} while ((Get-Date) -lt $Deadline)

$Remaining = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$RemainingPids = @($Remaining | Select-Object -ExpandProperty OwningProcess -Unique)
$RecordedPids = @()
if ($State -and $State.listener_pid) { $RecordedPids += [int]$State.listener_pid }
if ($State -and $State.launcher_pid) { $RecordedPids += [int]$State.launcher_pid }
$RecordedPids = @($RecordedPids | Select-Object -Unique)
$OwnedRemaining = @($RemainingPids | Where-Object { $RecordedPids -contains [int]$_ })

if ($OwnedRemaining.Count -gt 0) {
    $AttemptJson = @($Attempts.ToArray()) | ConvertTo-Json -Depth 10 -Compress
    throw "The recorded SuperAssistant listener is still active on port $Port. PID: $($OwnedRemaining -join ', '). Attempts: $AttemptJson"
}

Remove-Item $StatePath -Force -ErrorAction SilentlyContinue
[ordered]@{
    stopped = $true
    state_path = $StatePath
    port = $Port
    attempts = @($Attempts.ToArray())
    remaining_listener_process_ids = $RemainingPids
    foreign_listeners_preserved = @($RemainingPids | Where-Object {
        -not ($RecordedPids -contains [int]$_)
    })
} | ConvertTo-Json -Depth 10
