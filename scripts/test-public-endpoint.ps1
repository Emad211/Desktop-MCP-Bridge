param(
    [Parameter(Mandatory=$true)][uri]$PublicBaseUrl,
    [int]$Attempts = 15,
    [int]$DelaySeconds = 2,
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml")
)

$ErrorActionPreference = "Stop"
if ($PublicBaseUrl.Scheme -ne "https") {
    throw "The public GPT Action endpoint must use HTTPS."
}
$Base = $PublicBaseUrl.AbsoluteUri.TrimEnd('/')
$Health = $null
for ($Index = 0; $Index -lt $Attempts; $Index++) {
    try {
        $Health = Invoke-RestMethod -Uri "$Base/health" -TimeoutSec 8
        if ($Health.ok -eq $true) { break }
    } catch {}
    Start-Sleep -Seconds $DelaySeconds
}
if (-not $Health -or $Health.ok -ne $true) {
    throw "Public health check failed after $Attempts attempts: $Base/health"
}

$Result = [ordered]@{
    url = $Base
    health = $Health
    authenticated_status = $null
    tested_at = (Get-Date).ToUniversalTime().ToString("o")
}
if (Test-Path $EncryptedKeyPath) {
    $Credential = Import-Clixml -Path $EncryptedKeyPath
    $Headers = @{ Authorization = "Bearer " + $Credential.GetNetworkCredential().Password }
    $Body = @{ operation = "status"; arguments = @{} } | ConvertTo-Json -Depth 10
    $Status = Invoke-RestMethod -Method Post -Uri "$Base/v1/observe" -Headers $Headers -ContentType "application/json" -Body $Body -TimeoutSec 15
    if ($Status.ok -ne $true) { throw "Authenticated public status check returned ok=false." }
    $Result.authenticated_status = $Status
}
$Result | ConvertTo-Json -Depth 12
