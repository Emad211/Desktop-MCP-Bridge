param(
    [string]$BaseUrl = "http://127.0.0.1:8766",
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml")
)

$ErrorActionPreference = "Stop"
$Health = $null
try { $Health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 3 } catch {}
$State = [ordered]@{
    online = [bool]$Health
    health = $Health
    kill_switch_active = Test-Path (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\STOP")
    encrypted_key_present = Test-Path $EncryptedKeyPath
    gateway_state = $null
    tunnel_state = $null
}
foreach ($Pair in @(@("gateway_state", "gateway.json"), @("tunnel_state", "quick-tunnel.json"))) {
    $Path = Join-Path $env:LOCALAPPDATA ("DesktopMCPBridge\" + $Pair[1])
    if (Test-Path $Path) {
        try { $State[$Pair[0]] = Get-Content $Path -Raw | ConvertFrom-Json } catch {}
    }
}
if ($Health -and (Test-Path $EncryptedKeyPath)) {
    $Credential = Import-Clixml -Path $EncryptedKeyPath
    $Headers = @{ Authorization = "Bearer " + $Credential.GetNetworkCredential().Password }
    $Body = @{ operation = "status"; arguments = @{} } | ConvertTo-Json -Depth 10
    try { $State.bridge = Invoke-RestMethod -Method Post -Uri "$($BaseUrl.TrimEnd('/'))/v1/observe" -Headers $Headers -ContentType "application/json" -Body $Body -TimeoutSec 5 } catch { $State.bridge_error = $_.Exception.Message }
}
$State | ConvertTo-Json -Depth 10
