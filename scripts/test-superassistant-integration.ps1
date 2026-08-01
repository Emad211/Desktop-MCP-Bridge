param(
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "full",
    [string[]]$AllowedRoot = @("C:\"),
    [ValidateSet("sse", "streamableHttp", "ws")]
    [string]$OutputTransport = "sse",
    [int]$Port = 3006,
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [string]$ProxyUrl = "",
    [string]$ProxyPackageVersion = "0.1.8",
    [switch]$InstallNodeIfMissing,
    [switch]$LeaveRunning,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "Project Python was not found. Run scripts/install.ps1 first."
}
if ($Profile -eq "full" -and -not $IUnderstand) {
    throw "Full SuperAssistant preflight requires -IUnderstand."
}

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$ConfigPath = Join-Path $StateDir "superassistant\config.json"
$StatePath = Join-Path $StateDir "superassistant-proxy.json"
$ReportPath = Join-Path $StateDir "superassistant-preflight.json"
$Report = [ordered]@{
    ok = $false
    repo_root = $RepoRoot
    git_sha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    profile = $Profile
    output_transport = $OutputTransport
    port = $Port
    requested_network_mode = $NetworkMode
    proxy_package_version = $ProxyPackageVersion
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    steps = [ordered]@{}
}

try {
    Write-Host "[1/6] Resolving VPN/network route for npm and preserving localhost bypass..." -ForegroundColor Cyan
    $NetworkArguments = @{ NetworkMode = $NetworkMode }
    if ($ProxyUrl) { $NetworkArguments.ProxyUrl = $ProxyUrl }
    $NetworkRaw = & (Join-Path $PSScriptRoot "get-superassistant-network-plan.ps1") @NetworkArguments
    $Network = $NetworkRaw | ConvertFrom-Json
    $Report.steps.network_plan = $Network
    if ($Network.ok -ne $true) {
        throw "No usable route to npm was found. Turn VPN/V2Ray on and rerun."
    }
    Write-Host "      Route=$($Network.resolved_mode); VPN/TUN likely active=$($Network.vpn_or_tun_likely_active)" -ForegroundColor DarkCyan

    Write-Host "[2/6] Exporting absolute MCP stdio configuration..." -ForegroundColor Cyan
    $ExportArguments = @{
        Profile = $Profile
        AllowedRoot = $AllowedRoot
        OutputPath = $ConfigPath
        IUnderstand = $IUnderstand
    }
    $ExportRaw = & (Join-Path $PSScriptRoot "export-superassistant-config.ps1") @ExportArguments
    $Export = $ExportRaw | ConvertFrom-Json
    if ($Export.ok -ne $true) { throw "Config export returned ok=false." }
    $Report.steps.config_export = $Export

    Write-Host "[3/6] Starting the MCP child directly and probing initialize/tools/list/bridge_status..." -ForegroundColor Cyan
    $ProbeRaw = & $Python (Join-Path $PSScriptRoot "probe_mcp_stdio.py") `
        --config $ConfigPath `
        --server desktop-mcp-bridge `
        --timeout 45
    if ($LASTEXITCODE -ne 0) {
        throw "MCP stdio probe failed: $($ProbeRaw | Out-String)"
    }
    $Probe = $ProbeRaw | ConvertFrom-Json
    if ($Probe.ok -ne $true) { throw "MCP stdio probe returned ok=false." }
    $Report.steps.mcp_stdio = $Probe

    Write-Host "[4/6] Starting the pinned local SuperAssistant proxy on localhost:$Port..." -ForegroundColor Cyan
    $StartArguments = @{
        OutputTransport = $OutputTransport
        Port = $Port
        ConfigPath = $ConfigPath
        NetworkMode = $NetworkMode
        ProxyPackageVersion = $ProxyPackageVersion
        InstallNodeIfMissing = $InstallNodeIfMissing
        Restart = $true
    }
    if ($ProxyUrl) { $StartArguments.ProxyUrl = $ProxyUrl }
    $StartRaw = & (Join-Path $PSScriptRoot "start-superassistant-proxy.ps1") @StartArguments
    $Start = $StartRaw | ConvertFrom-Json
    if ($Start.owned_listener_healthy -ne $true) {
        throw "SuperAssistant proxy startup did not produce a healthy owned listener."
    }
    $Report.steps.proxy_start = $Start

    Write-Host "[5/6] Probing the browser-facing transport through the local proxy..." -ForegroundColor Cyan
    if ($OutputTransport -eq "sse") {
        $SseProbeRaw = & $Python (Join-Path $PSScriptRoot "probe_superassistant_sse.py") `
            --endpoint $Start.endpoint `
            --timeout 45
        if ($LASTEXITCODE -ne 0) {
            throw "SuperAssistant SSE probe failed: $($SseProbeRaw | Out-String)"
        }
        $SseProbe = $SseProbeRaw | ConvertFrom-Json
        if ($SseProbe.ok -ne $true) { throw "SuperAssistant SSE probe returned ok=false." }
        $Report.steps.browser_transport = $SseProbe
    } else {
        $Report.steps.browser_transport = [ordered]@{
            ok = $true
            skipped = $true
            reason = "Only the SSE extension path is part of Gate C acceptance."
            output_transport = $OutputTransport
        }
    }

    Write-Host "[6/6] Verifying listener ownership, child connection, and extension handoff..." -ForegroundColor Cyan
    $StatusRaw = & (Join-Path $PSScriptRoot "status-superassistant-proxy.ps1") `
        -Port $Port `
        -StatePath $StatePath
    $Status = $StatusRaw | ConvertFrom-Json
    if ($Status.owned_listener_healthy -ne $true) {
        throw "SuperAssistant proxy status is not healthy."
    }
    if ($Status.foreign_listener_process_ids.Count -gt 0) {
        throw "Foreign listeners were detected on the proxy port."
    }
    $Report.steps.proxy_status = $Status

    $Report.ok = $true
    $Report.extension_handoff = [ordered]@{
        endpoint = $Status.endpoint
        transport = $OutputTransport
        instructions_path = (Join-Path $RepoRoot "gpt\SUPERASSISTANT_INSTRUCTIONS.md")
        auto_execute_default = $false
        auto_submit_default = $false
        vpn_instruction = "Keep VPN on for the first browser acceptance test. Localhost is bypassed through NO_PROXY."
        next_action = "Open ChatGPT web, reload MCP SuperAssistant, connect to the endpoint, refresh tools, and insert the instructions file."
    }
    Write-Host "Preflight passed. Endpoint: $($Status.endpoint)" -ForegroundColor Green
} catch {
    $Report.error = [ordered]@{
        type = $_.Exception.GetType().Name
        message = $_.Exception.Message
    }
    Write-Host "Preflight failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    if (-not $LeaveRunning) {
        try {
            $StopRaw = & (Join-Path $PSScriptRoot "stop-superassistant-proxy.ps1") `
                -Port $Port `
                -StatePath $StatePath
            $Report.steps.proxy_stop = $StopRaw | ConvertFrom-Json
        } catch {
            $Report.stop_error = $_.Exception.Message
        }
    }
    $Report.finished_at = (Get-Date).ToUniversalTime().ToString("o")
    New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force | Out-Null
    $Report | ConvertTo-Json -Depth 30 | Set-Content -Path $ReportPath -Encoding UTF8
    $Report | ConvertTo-Json -Depth 30
}
