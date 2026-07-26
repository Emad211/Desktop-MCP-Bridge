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
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$InvocationParameters = @{} + $PSBoundParameters
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$ReportPath = Join-Path $StateDir "repair-report.json"

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-SelfElevated {
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath),
        "-NoAutoElevate",
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
    if ($NoAutoElevate) { throw "The elevated repair session is still not Administrator." }
    Invoke-SelfElevated
}

$Report = [ordered]@{
    repo_root = $RepoRoot
    git_sha = (& git rev-parse HEAD).Trim()
    administrator = Test-Administrator
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    steps = [ordered]@{}
}

try {
    & (Join-Path $PSScriptRoot "stop-tunnel-supervisor.ps1") -StopTunnel | Out-Null
    & (Join-Path $PSScriptRoot "stop-gateway.ps1") | Out-Null
    $Report.steps.stop_previous = "ok"

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
        & (Join-Path $PSScriptRoot "install-autostart.ps1") `
            -FullAccess:$FullAccess `
            -Autonomous:$Autonomous `
            -IUnderstand:$IUnderstand
        $Report.steps.gateway_autostart = "installed"
    }

    $Gateway = & (Join-Path $PSScriptRoot "start-gateway.ps1") `
        -Restart `
        -FullAccess:$FullAccess `
        -Autonomous:$Autonomous `
        -IUnderstand:$IUnderstand | ConvertFrom-Json
    $Report.gateway = $Gateway

    $Diagnostics = & (Join-Path $PSScriptRoot "diagnose.ps1") -TestScreen -TestNetwork | ConvertFrom-Json
    $Report.diagnostics = $Diagnostics
    $SelfTest = & (Join-Path $PSScriptRoot "self-test.ps1") | ConvertFrom-Json
    $Report.self_test = $SelfTest

    if ($StartTunnel) {
        $TunnelArguments = @{
            Provider = $TunnelProvider
            NetworkMode = $NetworkMode
            Port = 8766
            InstallIfMissing = $InstallIfMissing
            LoginIfNeeded = $LoginIfNeeded
            Restart = $true
        }
        if ($NgrokAuthToken) { $TunnelArguments.NgrokAuthToken = $NgrokAuthToken }
        $Tunnel = & (Join-Path $PSScriptRoot "start-tunnel.ps1") @TunnelArguments | ConvertFrom-Json
        if (-not $AllowEphemeral -and -not [bool]$Tunnel.stable_url) {
            throw "A tunnel was created, but its URL is ephemeral. Configure ngrok/Tailscale or rerun with -AllowEphemeral."
        }
        $Report.tunnel = $Tunnel
        $Export = & (Join-Path $PSScriptRoot "export-gpt-config.ps1") -PublicBaseUrl $Tunnel.url | ConvertFrom-Json
        $Report.gpt_config = $Export

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
        $Report.tunnel_supervisor = & (Join-Path $PSScriptRoot "start-tunnel-supervisor.ps1") @SupervisorArguments | ConvertFrom-Json
    }

    $Status = & (Join-Path $PSScriptRoot "status.ps1") -IncludeNetworkProfile | ConvertFrom-Json
    $Report.status = $Status
    $Report.ok = $true
} catch {
    $Report.ok = $false
    $Report.error = $_.Exception.Message
    throw
} finally {
    $Report.finished_at = (Get-Date).ToUniversalTime().ToString("o")
    $Report | ConvertTo-Json -Depth 30 | Set-Content $ReportPath -Encoding UTF8
    Write-Host "Repair report: $ReportPath" -ForegroundColor Cyan
    $Report | ConvertTo-Json -Depth 30
}
