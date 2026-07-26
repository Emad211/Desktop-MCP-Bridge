param(
    [int]$Port = 8766,
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$IUnderstand,
    [switch]$Restart,
    [switch]$RequireAdministrator
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "gateway.json"
$OutLog = Join-Path $StateDir "gateway.stdout.log"
$ErrLog = Join-Path $StateDir "gateway.stderr.log"
$EncryptedKeyPath = Join-Path $StateDir "action-key.clixml"
$DesiredProfile = if ($FullAccess) { "full" } else { "safe" }
$DesiredPolicy = if ($Autonomous) { "autonomous" } else { "guarded" }
$CallerAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if ($FullAccess -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand."
}
if ($RequireAdministrator -and -not $CallerAdministrator) {
    throw "Administrator rights are required for this gateway start. Relaunch through the elevated repair workflow."
}
if (-not (Test-Path $EncryptedKeyPath)) {
    throw "Encrypted Action key not found: $EncryptedKeyPath"
}
$Credential = Import-Clixml -Path $EncryptedKeyPath
$Headers = @{ Authorization = "Bearer " + $Credential.GetNetworkCredential().Password }

function Get-DetailedGatewayStatus {
    try {
        $Body = @{ operation = "status"; arguments = @{} } | ConvertTo-Json -Depth 5
        $Response = Invoke-RestMethod `
            -Method Post `
            -Uri "http://127.0.0.1:$Port/v1/observe" `
            -Headers $Headers `
            -ContentType "application/json" `
            -Body $Body `
            -TimeoutSec 3
        if ($Response.ok -eq $true -and $Response.result) { return $Response.result }
    } catch {}
    return $null
}

function Test-ProcessDescendant {
    param([int]$ProcessId, [int]$AncestorProcessId)
    $Current = $ProcessId
    for ($Depth = 0; $Depth -lt 12; $Depth++) {
        if ($Current -eq $AncestorProcessId) { return $true }
        try {
            $Row = Get-CimInstance Win32_Process -Filter "ProcessId=$Current" -ErrorAction Stop
        } catch {
            return $false
        }
        if (-not $Row.ParentProcessId -or $Row.ParentProcessId -eq $Current) { return $false }
        $Current = [int]$Row.ParentProcessId
    }
    return $false
}

function Test-CompatibleStatus {
    param($Status)
    if (-not $Status) { return $false }
    if ($Status.access_profile -ne $DesiredProfile) { return $false }
    if ($Status.approval_policy -ne $DesiredPolicy) { return $false }
    if ($FullAccess -and $Status.full_access_active -ne $true) { return $false }
    if ($RequireAdministrator -and $Status.administrator -ne $true) { return $false }
    return $true
}

$Existing = Get-DetailedGatewayStatus
if ($Existing -and -not $Restart) {
    if (-not (Test-CompatibleStatus $Existing)) {
        throw "An incompatible gateway already owns port $Port (PID $($Existing.process_id), profile=$($Existing.access_profile), policy=$($Existing.approval_policy), administrator=$($Existing.administrator)). Use -Restart from the required privilege level."
    }
    [ordered]@{
        ok = $true
        reused = $true
        gateway = $Existing
        state_path = $StatePath
    } | ConvertTo-Json -Depth 10
    exit 0
}

if ($Restart -or $Existing) {
    & (Join-Path $PSScriptRoot "stop-gateway.ps1") -Port $Port -WaitSeconds 20 | Out-Null
}

$RunScript = Join-Path $PSScriptRoot "run-actions.ps1"
$Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $RunScript),
    "-Port", "$Port"
)
if ($FullAccess) { $Arguments += @("-FullAccess", "-IUnderstand") }
if ($Autonomous) { $Arguments += "-Autonomous" }

Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
$Launcher = Start-Process -FilePath "powershell.exe" `
    -ArgumentList ($Arguments -join " ") `
    -WorkingDirectory $RepoRoot `
    -WindowStyle Minimized `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -PassThru

$Deadline = (Get-Date).AddSeconds(60)
do {
    Start-Sleep -Milliseconds 500
    $Detailed = Get-DetailedGatewayStatus
    if ($Detailed) {
        $IsOwned = Test-ProcessDescendant -ProcessId ([int]$Detailed.process_id) -AncestorProcessId $Launcher.Id
        if (-not $IsOwned) {
            try { & taskkill.exe /PID $Launcher.Id /T /F | Out-Null } catch {}
            throw "Port $Port became healthy through an unexpected process (gateway PID $($Detailed.process_id), launcher PID $($Launcher.Id)). Refusing to claim a stale or competing gateway."
        }
        if (-not (Test-CompatibleStatus $Detailed)) {
            try { & taskkill.exe /PID $Launcher.Id /T /F | Out-Null } catch {}
            throw "Started gateway does not match the requested state: profile=$($Detailed.access_profile), policy=$($Detailed.approval_policy), administrator=$($Detailed.administrator)."
        }
        $State = [ordered]@{
            launcher_pid = $Launcher.Id
            gateway_pid = [int]$Detailed.process_id
            port = $Port
            profile = $Detailed.access_profile
            approval_policy = $Detailed.approval_policy
            administrator = [bool]$Detailed.administrator
            process_started_at = $Detailed.process_started_at
            started_at = (Get-Date).ToUniversalTime().ToString("o")
            stdout_log = $OutLog
            stderr_log = $ErrLog
        }
        $State | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding UTF8
        [ordered]@{
            ok = $true
            reused = $false
            gateway = $Detailed
            launcher_pid = $Launcher.Id
            state_path = $StatePath
            stdout_log = $OutLog
            stderr_log = $ErrLog
        } | ConvertTo-Json -Depth 12
        exit 0
    }
    if ($Launcher.HasExited) {
        $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "Gateway launcher exited before verified startup. Exit code: $($Launcher.ExitCode). $ErrorText"
    }
} while ((Get-Date) -lt $Deadline)

try { & taskkill.exe /PID $Launcher.Id /T /F | Out-Null } catch {}
throw "Gateway did not reach a verified profile/privilege state within 60 seconds. Inspect $ErrLog"
