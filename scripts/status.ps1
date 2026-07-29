param(
    [string]$BaseUrl = "http://127.0.0.1:8766",
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml"),
    [switch]$IncludeNetworkProfile
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$CallerAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
$Health = $null
try { $Health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 3 } catch {}
$Port = ([uri]$BaseUrl).Port
$Listeners = @(Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$ListenerProcessIds = @($Listeners | Select-Object -ExpandProperty OwningProcess -Unique)

$State = [ordered]@{
    online = [bool]$Health
    health = $Health
    caller_administrator = $CallerAdministrator
    administrator = $null
    gateway_administrator = $null
    gateway_process_id = $null
    listener_process_ids = $ListenerProcessIds
    multiple_gateway_listeners = $ListenerProcessIds.Count -gt 1
    gateway_identity_consistent = $null
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
        if ($State.bridge.ok -eq $true -and $State.bridge.result) {
            $Gateway = $State.bridge.result
            $State.gateway_process_id = [int]$Gateway.process_id
            $State.gateway_administrator = [bool]$Gateway.administrator
            $State.administrator = [bool]$Gateway.administrator
            $State.gateway_identity_consistent = (
                $ListenerProcessIds.Count -eq 1 -and
                [int]$ListenerProcessIds[0] -eq [int]$Gateway.process_id -and
                (
                    -not $State.gateway_state -or
                    -not $State.gateway_state.gateway_pid -or
                    [int]$State.gateway_state.gateway_pid -eq [int]$Gateway.process_id
                )
            )
        }
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
