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
    [string]$NgrokAuthToken = $env:NGROK_AUTHTOKEN,
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$AllowEphemeral,
    [switch]$NoAutoElevate,
    [string]$RepairRunId = "",
    [string]$ProgressPath = "",
    [string]$ReportPath = "",
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$InvocationParameters = @{} + $PSBoundParameters
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
if (-not $RepairRunId) { $RepairRunId = [guid]::NewGuid().ToString() }
if (-not $ProgressPath) { $ProgressPath = Join-Path $StateDir "repair-progress.json" }
if (-not $ReportPath) { $ReportPath = Join-Path $StateDir "repair-report.json" }

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Write-RepairProgress {
    param(
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Extra = @{}
    )
    $Payload = [ordered]@{
        repair_run_id = $RepairRunId
        status = $Status
        step = $Step
        message = $Message
        repair_pid = $PID
        administrator = Test-Administrator
        progress_path = $ProgressPath
        report_path = $ReportPath
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    foreach ($Key in $Extra.Keys) { $Payload[$Key] = $Extra[$Key] }
    $Temporary = "$ProgressPath.$PID.tmp"
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -Path $Temporary -Encoding UTF8
    Move-Item -Path $Temporary -Destination $ProgressPath -Force
}

function ConvertFrom-CommandJson {
    param(
        [object[]]$Output,
        [string]$CommandName
    )
    $Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$CommandName returned no JSON output."
    }
    try { return $Text | ConvertFrom-Json }
    catch {
        $Lines = $Text -split "`r?`n"
        for ($Index = $Lines.Count - 1; $Index -ge 0; $Index--) {
            $Trimmed = $Lines[$Index].TrimStart()
            if (-not ($Trimmed.StartsWith("{") -or $Trimmed.StartsWith("["))) { continue }
            $Candidate = ($Lines[$Index..($Lines.Count - 1)] -join "`n")
            try { return $Candidate | ConvertFrom-Json } catch {}
        }
        $Preview = if ($Text.Length -gt 4000) { $Text.Substring($Text.Length - 4000) } else { $Text }
        throw "$CommandName returned invalid mixed output instead of terminal JSON. Output tail: $Preview"
    }
}

function Invoke-SelfElevated {
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath),
        "-NoAutoElevate",
        "-RepairRunId", ('"{0}"' -f $RepairRunId),
        "-ProgressPath", ('"{0}"' -f $ProgressPath),
        "-ReportPath", ('"{0}"' -f $ReportPath),
        "-TunnelProvider", $TunnelProvider,
        "-NetworkMode", $NetworkMode
    )
    foreach ($SwitchName in @(
        "FullAccess",
        "Autonomous",
        "InstallAutostart",
        "StartTunnel",
        "InstallTunnelAutostart",
        "InstallIfMissing",
        "LoginIfNeeded",
        "AllowEphemeral",
        "IUnderstand"
    )) {
        if ($InvocationParameters.ContainsKey($SwitchName) -and $InvocationParameters[$SwitchName]) {
            $Arguments += "-$SwitchName"
        }
    }
    $PreviousToken = [Environment]::GetEnvironmentVariable("NGROK_AUTHTOKEN", "Process")
    if ($NgrokAuthToken) {
        [Environment]::SetEnvironmentVariable("NGROK_AUTHTOKEN", $NgrokAuthToken, "Process")
    }
    Write-RepairProgress -Status "awaiting_uac" -Step "elevation" -Message "Approve the Windows UAC prompt to continue."
    Write-Host "Opening an elevated repair session. Approve the UAC prompt." -ForegroundColor Yellow
    try {
        $Child = Start-Process -FilePath "powershell.exe" `
            -ArgumentList ($Arguments -join " ") `
            -WorkingDirectory $RepoRoot `
            -Verb RunAs `
            -Wait `
            -PassThru
    } finally {
        [Environment]::SetEnvironmentVariable("NGROK_AUTHTOKEN", $PreviousToken, "Process")
    }
    exit $Child.ExitCode
}

if ($FullAccess -and -not $IUnderstand) {
    throw "Full access repair requires -IUnderstand."
}
if (($FullAccess -or $InstallAutostart -or $InstallTunnelAutostart) -and -not (Test-Administrator)) {
    if ($NoAutoElevate) { throw "The elevated repair process is still not Administrator." }
    Invoke-SelfElevated
}

$Report = [ordered]@{
    repair_run_id = $RepairRunId
    repo_root = $RepoRoot
    git_sha = (& git rev-parse HEAD).Trim()
    administrator = Test-Administrator
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    steps = [ordered]@{}
}

Write-RepairProgress -Status "running" -Step "initializing" -Message "Elevated repair has started."
try {
    Write-RepairProgress -Status "running" -Step "stop_previous" -Message "Stopping prior gateway and tunnel processes."
    & (Join-Path $PSScriptRoot "stop-tunnel-supervisor.ps1") -StopTunnel | Out-Null
    & (Join-Path $PSScriptRoot "stop-gateway.ps1") -WaitSeconds 20 | Out-Null
    $Report.steps.stop_previous = "ok"

    Write-RepairProgress -Status "running" -Step "install" -Message "Repairing dependencies and browser/OCR runtime."
    & (Join-Path $PSScriptRoot "install.ps1")
    $Report.steps.install = "ok"

    $EncryptedKeyPath = Join-Path $StateDir "action-key.clixml"
    if (-not (Test-Path $EncryptedKeyPath)) {
        $Key = & (Join-Path $PSScriptRoot "new-action-key.ps1")
        & (Join-Path $PSScriptRoot "save-action-key.ps1") -ApiKey $Key
        Remove-Variable Key -ErrorAction SilentlyContinue
        $Report.steps.dpapi_key = "created"
    } else {
        $Report.steps.dpapi_key = "preserved"
    }

    if ($InstallAutostart) {
        Write-RepairProgress -Status "running" -Step "gateway_autostart" -Message "Installing the highest-privilege gateway logon task."
        & (Join-Path $PSScriptRoot "install-autostart.ps1") `
            -FullAccess:$FullAccess `
            -Autonomous:$Autonomous `
            -IUnderstand:$IUnderstand
        $Report.steps.gateway_autostart = "installed"
    }

    Write-RepairProgress -Status "running" -Step "gateway_start" -Message "Starting and verifying one elevated gateway instance."
    $GatewayOutput = @(& (Join-Path $PSScriptRoot "start-gateway.ps1") `
        -Restart `
        -RequireAdministrator:$FullAccess `
        -FullAccess:$FullAccess `
        -Autonomous:$Autonomous `
        -IUnderstand:$IUnderstand)
    $Gateway = ConvertFrom-CommandJson -Output $GatewayOutput -CommandName "start-gateway.ps1"
    $Report.gateway = $Gateway
    if ($FullAccess -and $Gateway.gateway.administrator -ne $true) {
        throw "Verified gateway is not elevated after Full Access repair."
    }

    Write-RepairProgress -Status "running" -Step "diagnostics" -Message "Running machine-readable diagnostics."
    $DiagnosticsOutput = @(& (Join-Path $PSScriptRoot "diagnose.ps1") -TestScreen -TestNetwork)
    $Diagnostics = ConvertFrom-CommandJson -Output $DiagnosticsOutput -CommandName "diagnose.ps1"
    $Report.diagnostics = $Diagnostics

    Write-RepairProgress -Status "running" -Step "self_test" -Message "Running end-to-end local self-test."
    $SelfTestOutput = @(& (Join-Path $PSScriptRoot "self-test.ps1"))
    $SelfTest = ConvertFrom-CommandJson -Output $SelfTestOutput -CommandName "self-test.ps1"
    $Report.self_test = $SelfTest

    if ($StartTunnel) {
        Write-RepairProgress -Status "running" -Step "tunnel" -Message "Starting and publicly verifying the tunnel."
        $TunnelArguments = @{
            Provider = $TunnelProvider
            NetworkMode = $NetworkMode
            Port = 8766
            InstallIfMissing = $InstallIfMissing
            LoginIfNeeded = $LoginIfNeeded
            Restart = $true
        }
        if ($NgrokAuthToken) { $TunnelArguments.NgrokAuthToken = $NgrokAuthToken }
        $TunnelOutput = @(& (Join-Path $PSScriptRoot "start-tunnel.ps1") @TunnelArguments)
        $Tunnel = ConvertFrom-CommandJson -Output $TunnelOutput -CommandName "start-tunnel.ps1"
        if (-not $AllowEphemeral -and -not [bool]$Tunnel.stable_url) {
            throw "A tunnel was created, but its URL is ephemeral. Configure ngrok/Tailscale or rerun with -AllowEphemeral."
        }
        $Report.tunnel = $Tunnel
        $ExportOutput = @(& (Join-Path $PSScriptRoot "export-gpt-config.ps1") -PublicBaseUrl $Tunnel.url)
        $Report.gpt_config = ConvertFrom-CommandJson -Output $ExportOutput -CommandName "export-gpt-config.ps1"

        if ($InstallTunnelAutostart) {
            & (Join-Path $PSScriptRoot "install-tunnel-autostart.ps1") `
                -Provider $TunnelProvider `
                -NetworkMode $NetworkMode `
                -InstallIfMissing:$InstallIfMissing `
                -LoginIfNeeded:$LoginIfNeeded `
                -AllowEphemeral:$AllowEphemeral
            $Report.steps.tunnel_autostart = "installed"
        }
        $SupervisorArguments = @{
            Provider = $TunnelProvider
            NetworkMode = $NetworkMode
            InstallIfMissing = $InstallIfMissing
            LoginIfNeeded = $LoginIfNeeded
            AllowEphemeral = $AllowEphemeral
            Restart = $true
        }
        if ($NgrokAuthToken) { $SupervisorArguments.NgrokAuthToken = $NgrokAuthToken }
        $SupervisorOutput = @(& (Join-Path $PSScriptRoot "start-tunnel-supervisor.ps1") @SupervisorArguments)
        $Report.tunnel_supervisor = ConvertFrom-CommandJson -Output $SupervisorOutput -CommandName "start-tunnel-supervisor.ps1"
    }

    Write-RepairProgress -Status "running" -Step "final_status" -Message "Verifying final process identity and privileges."
    $StatusOutput = @(& (Join-Path $PSScriptRoot "status.ps1") -IncludeNetworkProfile)
    $FinalStatus = ConvertFrom-CommandJson -Output $StatusOutput -CommandName "status.ps1"
    $Report.status = $FinalStatus
    if ($FinalStatus.gateway_identity_consistent -ne $true) {
        throw "Final gateway process identity is inconsistent with the listener/state file."
    }
    if ($FullAccess -and $FinalStatus.gateway_administrator -ne $true) {
        throw "Final gateway is not Administrator."
    }
    $Report.ok = $true
    Write-RepairProgress -Status "completed" -Step "complete" -Message "Repair completed and final state was verified." -Extra @{
        gateway_process_id = $FinalStatus.gateway_process_id
        gateway_administrator = $FinalStatus.gateway_administrator
    }
} catch {
    $Report.ok = $false
    $Report.error = $_.Exception.Message
    Write-RepairProgress -Status "failed" -Step "error" -Message $_.Exception.Message
    throw
} finally {
    $Report.finished_at = (Get-Date).ToUniversalTime().ToString("o")
    $Report | ConvertTo-Json -Depth 30 | Set-Content $ReportPath -Encoding UTF8
    Write-Host "Repair report: $ReportPath" -ForegroundColor Cyan
    $Report | ConvertTo-Json -Depth 30
}
