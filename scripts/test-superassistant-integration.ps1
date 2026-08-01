param(
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "full",
    [string[]]$AllowedRoot = @("C:\"),
    [ValidateSet("sse", "streamableHttp", "ws")]
    [string]$OutputTransport = "sse",
    [int]$Port = 3006,
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
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    steps = [ordered]@{}
}

try {
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

    $StartRaw = & (Join-Path $PSScriptRoot "start-superassistant-proxy.ps1") `
        -OutputTransport $OutputTransport `
        -Port $Port `
        -ConfigPath $ConfigPath `
        -InstallNodeIfMissing:$InstallNodeIfMissing `
        -Restart
    $Start = $StartRaw | ConvertFrom-Json
    if ($Start.owned_listener_healthy -ne $true) {
        throw "SuperAssistant proxy startup did not produce a healthy owned listener."
    }
    $Report.steps.proxy_start = $Start

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
        next_action = "Open ChatGPT web, reload MCP SuperAssistant, connect to the endpoint, refresh tools, and insert the instructions file."
    }
} catch {
    $Report.error = [ordered]@{
        type = $_.Exception.GetType().Name
        message = $_.Exception.Message
    }
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
