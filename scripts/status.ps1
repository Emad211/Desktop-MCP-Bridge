param(
    [string]$BaseUrl = "http://127.0.0.1:8766",
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml"),
    [switch]$IncludeNetworkProfile
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$Health = $null
try { $Health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 3 } catch {}
$State = [ordered]@{
    online = [bool]$Health
    health = $Health
    administrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    kill_switch_active = Test-Path (Join-Path $StateDir "STOP")
    encrypted_key_present = Test-Path $EncryptedKeyPath
    gateway_state = $null
    tunnel_state = $null
    tunnel_supervisor_state = $null
    endpoint_change = $null
    browser_runtime = $null
    gateway_autostart = [bool](Get-ScheduledTask -TaskName "Desktop MCP Bridge Action Gateway" -ErrorAction SilentlyContinue)
    tunnel_autostart = [bool](Get-ScheduledTask -TaskName "Desktop MCP Bridge Tunnel Supervisor" -ErrorAction SilentlyContinue)
}
foreach ($Pair in @(
    @("gateway_state", "gateway.json"),
    @("tunnel_state", "tunnel.json"),
    @("tunnel_supervisor_state", "tunnel-supervisor.json"),
    @("endpoint_change", "endpoint-change.json"),
    @("browser_runtime", "browser-runtime.json")
)) {
    $Path = Join-Path $StateDir $Pair[1]
    if (Test-Path $Path) {
        try { $State[$Pair[0]] = Get-Content $Path -Raw | ConvertFrom-Json } catch {}
    }
}
if ($Health -and (Test-Path $EncryptedKeyPath)) {
    $Credential = Import-Clixml -Path $EncryptedKeyPath
    $Headers = @{ Authorization = "Bearer " + $Credential.GetNetworkCredential().Password }
    $Body = @{ operation = "status"; arguments = @{} } | ConvertTo-Json -Depth 10
    try {
        $State.bridge = Invoke-RestMethod -Method Post -Uri "$($BaseUrl.TrimEnd('/'))/v1/observe" -Headers $Headers -ContentType "application/json" -Body $Body -TimeoutSec 5
    } catch {
        $State.bridge_error = $_.Exception.Message
    }
}
if ($State.tunnel_state -and $State.tunnel_state.url) {
    try {
        $PublicHealth = Invoke-RestMethod -Uri "$($State.tunnel_state.url.TrimEnd('/'))/health" -TimeoutSec 8
        $State.public_endpoint_healthy = $PublicHealth.ok -eq $true
    } catch {
        $State.public_endpoint_healthy = $false
    }
}
if ($IncludeNetworkProfile) {
    try {
        $State.network_profile = & (Join-Path $PSScriptRoot "get-network-profile.ps1") | ConvertFrom-Json
    } catch {
        $State.network_profile_error = $_.Exception.Message
    }
}
$State | ConvertTo-Json -Depth 20
