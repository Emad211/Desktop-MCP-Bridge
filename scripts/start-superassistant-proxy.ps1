param(
    [ValidateSet("sse", "streamableHttp", "ws")]
    [string]$OutputTransport = "sse",
    [int]$Port = 3006,
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant\config.json"),
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [string]$ProxyUrl = "",
    [string]$ProxyPackageVersion = "0.1.8",
    [int]$StartupTimeoutSeconds = 120,
    [switch]$InstallNodeIfMissing,
    [switch]$RefreshProxyRuntime,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$RuntimeDir = Join-Path $StateDir "superassistant-runtime"
New-Item -ItemType Directory -Path $StateDir, $RuntimeDir -Force | Out-Null
$StatePath = Join-Path $StateDir "superassistant-proxy.json"
$OutLog = Join-Path $StateDir "superassistant-proxy.stdout.log"
$ErrLog = Join-Path $StateDir "superassistant-proxy.stderr.log"
$InstallOutLog = Join-Path $StateDir "superassistant-runtime-install.stdout.log"
$InstallErrLog = Join-Path $StateDir "superassistant-runtime-install.stderr.log"

function Get-CommandPath {
    param([string[]]$Names)
    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) { return $Command.Source }
    }
    return $null
}

function Install-NodeRuntime {
    if (-not $InstallNodeIfMissing) {
        throw "node/npm was not found. Install Node.js LTS or rerun with -InstallNodeIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required for automatic Node.js installation."
    }
    & winget install --id OpenJS.NodeJS.LTS --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        throw "Node.js LTS installation failed with exit code $LASTEXITCODE."
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [Environment]::GetEnvironmentVariable("Path", "User")
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

function Save-ProcessEnvironment {
    param([string[]]$Names)
    $Saved = @{}
    foreach ($Name in $Names) {
        $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    }
    return $Saved
}

function Restore-ProcessEnvironment {
    param([hashtable]$Saved)
    foreach ($Name in $Saved.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process")
    }
}

function Set-NetworkEnvironment {
    param([object]$NetworkPlan, [string]$RequestedMode)
    $env:NO_PROXY = [string]$NetworkPlan.local_bypass
    $env:no_proxy = [string]$NetworkPlan.local_bypass
    $env:NPM_CONFIG_FETCH_TIMEOUT = "30000"
    $env:NPM_CONFIG_FETCH_RETRIES = "1"
    $env:NPM_CONFIG_PREFER_OFFLINE = "true"
    $env:NPM_CONFIG_AUDIT = "false"
    $env:NPM_CONFIG_FUND = "false"

    if ($NetworkPlan.resolved_mode -eq "proxy") {
        $SelectedProxy = [string]$NetworkPlan.selected_proxy
        $env:HTTP_PROXY = $SelectedProxy
        $env:HTTPS_PROXY = $SelectedProxy
        $env:http_proxy = $SelectedProxy
        $env:https_proxy = $SelectedProxy
        $env:NPM_CONFIG_PROXY = $SelectedProxy
        $env:NPM_CONFIG_HTTPS_PROXY = $SelectedProxy
    } elseif ($RequestedMode -eq "direct") {
        foreach ($Name in @(
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
            "http_proxy", "https_proxy", "all_proxy",
            "NPM_CONFIG_PROXY", "NPM_CONFIG_HTTPS_PROXY"
        )) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-ProxyEntry {
    param([string]$PackageRoot)
    $ManifestPath = Join-Path $PackageRoot "package.json"
    if (-not (Test-Path $ManifestPath)) {
        throw "Proxy package manifest was not found: $ManifestPath"
    }
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $BinRelative = $null
    if ($Manifest.bin -is [string]) {
        $BinRelative = [string]$Manifest.bin
    } elseif ($Manifest.bin) {
        $Preferred = $Manifest.bin.PSObject.Properties |
            Where-Object { $_.Name -eq "mcp-superassistant-proxy" } |
            Select-Object -First 1
        if ($Preferred) {
            $BinRelative = [string]$Preferred.Value
        } else {
            $First = $Manifest.bin.PSObject.Properties | Select-Object -First 1
            if ($First) { $BinRelative = [string]$First.Value }
        }
    }
    if (-not $BinRelative) {
        $Fallback = Join-Path $PackageRoot "dist\index.js"
        if (Test-Path $Fallback) { return (Resolve-Path $Fallback).Path }
        throw "The proxy package exposes no executable bin entry."
    }
    $Entry = Join-Path $PackageRoot $BinRelative
    if (-not (Test-Path $Entry)) {
        throw "Proxy executable entry was not found: $Entry"
    }
    return (Resolve-Path $Entry).Path
}

if (-not (Test-Path $ConfigPath)) {
    throw "SuperAssistant config was not found: $ConfigPath. Run scripts/export-superassistant-config.ps1 first."
}
try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $Config.mcpServers.'desktop-mcp-bridge') {
        throw "The config contains no desktop-mcp-bridge server."
    }
} catch {
    throw "Invalid SuperAssistant config: $($_.Exception.Message)"
}

if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-superassistant-proxy.ps1") -Port $Port -StatePath $StatePath | Out-Null
}

$ExistingListeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($ExistingListeners.Count -gt 0) {
    $Status = & (Join-Path $PSScriptRoot "status-superassistant-proxy.ps1") -Port $Port -StatePath $StatePath | ConvertFrom-Json
    if ($Status.owned_listener_healthy) {
        $Status | ConvertTo-Json -Depth 10
        return
    }
    $Pids = @($ExistingListeners | Select-Object -ExpandProperty OwningProcess -Unique)
    throw "Port $Port is already in use by an unverified process. PIDs: $($Pids -join ', '). Refusing to terminate it."
}

$Node = Get-CommandPath -Names @("node.exe", "node")
$Npm = Get-CommandPath -Names @("npm.cmd", "npm.exe", "npm")
if (-not $Node -or -not $Npm) {
    Install-NodeRuntime
    $Node = Get-CommandPath -Names @("node.exe", "node")
    $Npm = Get-CommandPath -Names @("npm.cmd", "npm.exe", "npm")
}
if (-not $Node -or -not $Npm) {
    throw "Node.js was installed but node/npm is still unavailable. Open a new PowerShell and retry."
}

$NetworkArguments = @{ NetworkMode = $NetworkMode }
if ($ProxyUrl) { $NetworkArguments.ProxyUrl = $ProxyUrl }
$NetworkPlanRaw = & (Join-Path $PSScriptRoot "get-superassistant-network-plan.ps1") @NetworkArguments
$NetworkPlan = $NetworkPlanRaw | ConvertFrom-Json
if ($NetworkPlan.ok -ne $true) {
    throw "The npm proxy package cannot be reached with the current network route. Turn VPN/V2Ray on and retry. Network plan: $($NetworkPlanRaw | Out-String)"
}
Write-Host "SuperAssistant network route: $($NetworkPlan.resolved_mode). $($NetworkPlan.bootstrap_instruction)" -ForegroundColor Cyan

$Endpoint = switch ($OutputTransport) {
    "sse" { "http://localhost:$Port/sse" }
    "streamableHttp" { "http://localhost:$Port/mcp" }
    "ws" { "ws://localhost:$Port/message" }
}

$Package = "@srbhptl39/mcp-superassistant-proxy@$ProxyPackageVersion"
$PackageRoot = Join-Path $RuntimeDir "node_modules\@srbhptl39\mcp-superassistant-proxy"
$ManifestPath = Join-Path $PackageRoot "package.json"
$InstalledVersion = $null
if (Test-Path $ManifestPath) {
    try { $InstalledVersion = (Get-Content $ManifestPath -Raw | ConvertFrom-Json).version } catch {}
}
$NeedsInstall = $RefreshProxyRuntime -or -not $InstalledVersion -or
    ([string]$InstalledVersion -ne [string]$ProxyPackageVersion)

$EnvironmentNames = @(
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
    "http_proxy", "https_proxy", "all_proxy",
    "NO_PROXY", "no_proxy",
    "NPM_CONFIG_PROXY", "NPM_CONFIG_HTTPS_PROXY",
    "NPM_CONFIG_FETCH_TIMEOUT", "NPM_CONFIG_FETCH_RETRIES",
    "NPM_CONFIG_PREFER_OFFLINE", "NPM_CONFIG_AUDIT", "NPM_CONFIG_FUND"
)
$SavedEnvironment = Save-ProcessEnvironment -Names $EnvironmentNames
try {
    Set-NetworkEnvironment -NetworkPlan $NetworkPlan -RequestedMode $NetworkMode

    if ($NeedsInstall) {
        Write-Host "Installing pinned SuperAssistant proxy runtime $ProxyPackageVersion (one-time/cacheable)..." -ForegroundColor Cyan
        $PackageJsonPath = Join-Path $RuntimeDir "package.json"
        if (-not (Test-Path $PackageJsonPath)) {
            '{"private":true}' | Set-Content -Path $PackageJsonPath -Encoding UTF8
        }
        Remove-Item $InstallOutLog, $InstallErrLog -Force -ErrorAction SilentlyContinue
        $InstallArguments = @(
            "install",
            "--prefix", ('"{0}"' -f $RuntimeDir),
            "--save-exact",
            "--omit=dev",
            "--no-package-lock",
            "--no-audit",
            "--no-fund",
            $Package
        )
        $NpmInstall = Start-Process -FilePath $Npm `
            -ArgumentList ($InstallArguments -join " ") `
            -WorkingDirectory $RuntimeDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput $InstallOutLog `
            -RedirectStandardError $InstallErrLog `
            -Wait `
            -PassThru
        if ($NpmInstall.ExitCode -ne 0) {
            $InstallStdout = if (Test-Path $InstallOutLog) { Get-Content $InstallOutLog -Raw } else { "" }
            $InstallStderr = if (Test-Path $InstallErrLog) { Get-Content $InstallErrLog -Raw } else { "" }
            throw "Installing the pinned proxy runtime failed with exit code $($NpmInstall.ExitCode). stdout='$InstallStdout' stderr='$InstallStderr'"
        }
        Write-Host "Pinned proxy runtime installed successfully." -ForegroundColor DarkCyan
    } else {
        Write-Host "Reusing cached SuperAssistant proxy runtime $InstalledVersion." -ForegroundColor DarkCyan
    }

    $ProxyEntry = Resolve-ProxyEntry -PackageRoot $PackageRoot
    Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
    $Arguments = @(
        ('"{0}"' -f $ProxyEntry),
        "--config", ('"{0}"' -f $ConfigPath),
        "--port", "$Port",
        "--outputTransport", $OutputTransport,
        "--logLevel", "info"
    )

    $Launcher = Start-Process -FilePath $Node `
        -ArgumentList ($Arguments -join " ") `
        -WorkingDirectory $RuntimeDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru
} finally {
    Restore-ProcessEnvironment -Saved $SavedEnvironment
}
$LauncherStartedAt = $Launcher.StartTime.ToUniversalTime().ToString("o")

$Deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
$ListenerPid = $null
$ListenerStartedAt = $null
$Connected = $false
do {
    Start-Sleep -Milliseconds 500
    if ($Launcher.HasExited) {
        $Stdout = if (Test-Path $OutLog) { Get-Content $OutLog -Raw } else { "" }
        $Stderr = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "SuperAssistant proxy exited during startup. Exit=$($Launcher.ExitCode). stdout='$Stdout' stderr='$Stderr'"
    }

    $Listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $Text = ""
    if (Test-Path $OutLog) { $Text += Get-Content $OutLog -Raw -ErrorAction SilentlyContinue }
    if (Test-Path $ErrLog) { $Text += "`n" + (Get-Content $ErrLog -Raw -ErrorAction SilentlyContinue) }
    if ($Text -match "(?im)Failed to connect to servers:\s*.*desktop-mcp-bridge") {
        throw "The proxy started but failed to initialize desktop-mcp-bridge. Inspect $OutLog and $ErrLog."
    }
    $Connected = $Text -match "(?im)Connected servers:\s*.*desktop-mcp-bridge" -or
        $Text -match "(?im)Connected to server:\s*desktop-mcp-bridge" -or
        $Text -match "(?im)Successfully initialized server:\s*desktop-mcp-bridge" -or (
            $Text -match "(?im)Connected to\s+1\s+of\s+1\s+servers"
        )
    if ($Listeners.Count -eq 1 -and $Connected) {
        $CandidatePid = [int]$Listeners[0].OwningProcess
        if (-not (Test-ProcessDescendant -ProcessId $CandidatePid -AncestorProcessId $Launcher.Id)) {
            & taskkill.exe /PID $Launcher.Id /T /F | Out-Null
            throw "Port $Port was opened by an unexpected process. Listener PID=$CandidatePid Launcher PID=$($Launcher.Id)."
        }
        $Listener = Get-Process -Id $CandidatePid -ErrorAction Stop
        $ListenerPid = $CandidatePid
        $ListenerStartedAt = $Listener.StartTime.ToUniversalTime().ToString("o")
        break
    }
} while ((Get-Date) -lt $Deadline)

if (-not $ListenerPid -or -not $Connected) {
    try { & taskkill.exe /PID $Launcher.Id /T /F | Out-Null } catch {}
    throw "SuperAssistant proxy did not reach a verified connected state within $StartupTimeoutSeconds seconds. Inspect $OutLog and $ErrLog."
}

$State = [ordered]@{
    provider = "mcp-superassistant-proxy"
    package = $Package
    package_version = $ProxyPackageVersion
    launch_method = "direct-node-hidden"
    runtime_dir = $RuntimeDir
    proxy_entry = $ProxyEntry
    node_path = $Node
    launcher_pid = $Launcher.Id
    launcher_started_at = $LauncherStartedAt
    listener_pid = $ListenerPid
    listener_started_at = $ListenerStartedAt
    port = $Port
    output_transport = $OutputTransport
    endpoint = $Endpoint
    config_path = $ConfigPath
    stdout_log = $OutLog
    stderr_log = $ErrLog
    runtime_install_stdout_log = $InstallOutLog
    runtime_install_stderr_log = $InstallErrLog
    started_at = (Get-Date).ToUniversalTime().ToString("o")
}
$State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8

$Status = & (Join-Path $PSScriptRoot "status-superassistant-proxy.ps1") -Port $Port -StatePath $StatePath | ConvertFrom-Json
if (-not $Status.owned_listener_healthy) {
    & (Join-Path $PSScriptRoot "stop-superassistant-proxy.ps1") -Port $Port -StatePath $StatePath | Out-Null
    throw "Proxy state was written, but final ownership/connection validation failed."
}
$Status | Add-Member -NotePropertyName network_plan -NotePropertyValue $NetworkPlan -Force
$Status | ConvertTo-Json -Depth 20
