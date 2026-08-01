param(
    [string]$SessionPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\chatgpt-gate-c-session.json"),
    [int]$Port = 3006
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $SessionPath)) {
    throw "Gate C session was not found: $SessionPath. Run scripts/prepare-chatgpt-gate-c.ps1 first."
}

$Session = Get-Content $SessionPath -Raw | ConvertFrom-Json
$RepoRoot = [string]$Session.repo_root
$AgentPath = [string]$Session.agent_created_path
$BlockedPath = [string]$Session.blocked_path
$ExpectedContent = [string]$Session.expected_content
$StatePath = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\superassistant-proxy.json"
$ReportPath = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\chatgpt-gate-c-verification.json"

$ProxyRaw = & (Join-Path $RepoRoot "scripts\status-superassistant-proxy.ps1") `
    -Port $Port `
    -StatePath $StatePath
$Proxy = $ProxyRaw | ConvertFrom-Json

$AgentExists = Test-Path $AgentPath
$ActualContent = if ($AgentExists) { (Get-Content $AgentPath -Raw).Trim() } else { $null }
$ContentMatches = $AgentExists -and $ActualContent -ceq $ExpectedContent
$BlockedAbsent = -not (Test-Path $BlockedPath)

$Python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
$AuditPath = $null
$AuditEvidence = $false
if (Test-Path $Python) {
    $AuditPath = (& $Python -c "from desktop_mcp_bridge.config import BridgeSettings; print(BridgeSettings().audit_log_path)").Trim()
    if ($AuditPath -and (Test-Path $AuditPath)) {
        $AuditEvidence = [bool](Select-String -Path $AuditPath -SimpleMatch $AgentPath -Quiet -ErrorAction SilentlyContinue)
        if (-not $AuditEvidence) {
            $AuditEvidence = [bool](Select-String -Path $AuditPath -SimpleMatch "write_text_file" -Quiet -ErrorAction SilentlyContinue)
        }
    }
}

$CorePassed = (
    $Proxy.owned_listener_healthy -eq $true -and
    $AgentExists -and
    $ContentMatches -and
    $AuditEvidence
)

$Report = [ordered]@{
    ok = $CorePassed
    verified_at = (Get-Date).ToUniversalTime().ToString("o")
    session_id = $Session.session_id
    git_sha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    proxy = [ordered]@{
        endpoint = $Proxy.endpoint
        owned_listener_healthy = $Proxy.owned_listener_healthy
        bridge_connected = $Proxy.bridge_connected
        foreign_listener_process_ids = $Proxy.foreign_listener_process_ids
    }
    chat_round_trip = [ordered]@{
        agent_file_exists = $AgentExists
        expected_content = $ExpectedContent
        actual_content = $ActualContent
        exact_content_match = $ContentMatches
        audit_path = $AuditPath
        audit_evidence = $AuditEvidence
    }
    kill_switch_negative = [ordered]@{
        blocked_file_absent = $BlockedAbsent
        note = "This proves only file absence. The rejected tool result must also be visually confirmed in ChatGPT."
    }
    next_gate = $(if ($CorePassed) {
        "Run the kill-switch negative test, then perform the VPN toggle resilience check."
    } else {
        "Repeat the missing Gate C prompt and inspect the proxy/audit state."
    })
}
$Report | ConvertTo-Json -Depth 20 | Set-Content -Path $ReportPath -Encoding UTF8
$Report | ConvertTo-Json -Depth 20

if (-not $CorePassed) {
    exit 1
}
