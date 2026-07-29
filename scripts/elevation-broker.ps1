param(
    [Parameter(Mandatory=$true)]
    [string]$RequestPath
)

$ErrorActionPreference = "Stop"

function Write-State {
    param(
        [string]$Path,
        [hashtable]$Payload
    )
    $Payload.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $Temporary = "$Path.$PID.tmp"
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -Path $Temporary -Encoding UTF8
    Move-Item -Path $Temporary -Destination $Path -Force
}

try {
    $Request = Get-Content $RequestPath -Raw | ConvertFrom-Json
    $State = @{
        repair_run_id = [string]$Request.repair_run_id
        status = "awaiting_uac"
        step = "elevation"
        message = "Approve the Windows UAC prompt to continue the repair."
        broker_pid = $PID
        request_path = $RequestPath
        progress_path = [string]$Request.progress_path
        report_path = [string]$Request.report_path
    }
    Write-State -Path $Request.progress_path -Payload $State

    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $Request.repair_script),
        "-NoAutoElevate",
        "-RepairRunId", ('"{0}"' -f $Request.repair_run_id),
        "-ProgressPath", ('"{0}"' -f $Request.progress_path),
        "-ReportPath", ('"{0}"' -f $Request.report_path),
        "-TunnelProvider", [string]$Request.tunnel_provider,
        "-NetworkMode", [string]$Request.network_mode
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
        $PropertyName = $SwitchName.Substring(0,1).ToLowerInvariant() + $SwitchName.Substring(1)
        if ([bool]$Request.$PropertyName) { $Arguments += "-$SwitchName" }
    }

    $Child = Start-Process -FilePath "powershell.exe" `
        -ArgumentList ($Arguments -join " ") `
        -WorkingDirectory ([string]$Request.repo_root) `
        -Verb RunAs `
        -Wait `
        -PassThru

    if ($Child.ExitCode -ne 0) {
        $Current = @{}
        if (Test-Path $Request.progress_path) {
            try {
                $Loaded = Get-Content $Request.progress_path -Raw | ConvertFrom-Json
                foreach ($Property in $Loaded.PSObject.Properties) { $Current[$Property.Name] = $Property.Value }
            } catch {}
        }
        $Current.repair_run_id = [string]$Request.repair_run_id
        $Current.status = "failed"
        $Current.step = "elevated_process"
        $Current.message = "The elevated repair process exited with code $($Child.ExitCode)."
        $Current.exit_code = $Child.ExitCode
        Write-State -Path $Request.progress_path -Payload $Current
    }
} catch {
    try {
        $FallbackPath = $null
        if ($Request -and $Request.progress_path) { $FallbackPath = [string]$Request.progress_path }
        if (-not $FallbackPath) { $FallbackPath = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\repair-progress.json" }
        Write-State -Path $FallbackPath -Payload @{
            repair_run_id = if ($Request) { [string]$Request.repair_run_id } else { $null }
            status = "failed"
            step = "elevation_broker"
            message = $_.Exception.Message
            broker_pid = $PID
        }
    } catch {}
    exit 1
}
