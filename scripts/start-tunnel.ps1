param(
    [ValidateSet("auto", "ngrok", "cloudflare", "tailscale")]
    [string]$Provider = "auto",
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [int]$Port = 8766,
    [string]$ProxyUrl = "",
    [string]$NgrokAuthToken = $env:NGROK_AUTHTOKEN,
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$Attempts = New-Object System.Collections.Generic.List[object]

function Get-SafeProxyUrl {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        $Uri = [uri]$Value
        if ($Uri.UserInfo) {
            return "$($Uri.Scheme)://***@$($Uri.Host):$($Uri.Port)"
        }
    } catch {}
    return $Value
}

function Test-NgrokConfigured {
    if ($NgrokAuthToken) { return $true }
    if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) { return $false }
    $Candidates = @(
        (Join-Path $env:LOCALAPPDATA "ngrok\ngrok.yml"),
        (Join-Path $env:USERPROFILE ".config\ngrok\ngrok.yml")
    )
    foreach ($Path in $Candidates) {
        if ((Test-Path $Path) -and (Select-String -Path $Path -Pattern '^\s*authtoken\s*:\s*\S+' -Quiet)) {
            return $true
        }
    }
    return $false
}

function Test-TailscaleReady {
    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) { return $false }
    try {
        $Status = & tailscale status --json | ConvertFrom-Json
        return $Status.BackendState -eq "Running"
    } catch {
        return $false
    }
}

try {
    $LocalHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($LocalHealth.ok -ne $true) { throw "Local gateway health returned ok=false." }
} catch {
    throw "The local Action Gateway is not healthy on 127.0.0.1:$Port."
}

if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
}

$Network = & (Join-Path $PSScriptRoot "get-network-profile.ps1") | ConvertFrom-Json
$Routes = New-Object System.Collections.Generic.List[object]
if ($ProxyUrl) {
    $Routes.Add([pscustomobject]@{ mode = "proxy"; proxy_url = $ProxyUrl; source = "explicit" })
}
if ($NetworkMode -in @("auto", "direct")) {
    $Routes.Add([pscustomobject]@{ mode = "direct"; proxy_url = ""; source = "direct" })
}
if ($NetworkMode -in @("auto", "proxy")) {
    foreach ($Candidate in @($Network.working_proxies)) {
        if ($Candidate.url -and -not ($Routes | Where-Object { $_.proxy_url -eq $Candidate.url })) {
            $Routes.Add([pscustomobject]@{
                mode = "proxy"
                proxy_url = [string]$Candidate.url
                source = [string]$Candidate.source
            })
        }
    }
}
if ($Routes.Count -eq 0) {
    throw "No usable direct or V2Ray/system proxy route was detected. Run scripts/get-network-profile.ps1 for details."
}

$NgrokReady = Test-NgrokConfigured
$TailscaleReady = Test-TailscaleReady
if ($Provider -eq "auto") {
    $ProviderOrder = New-Object System.Collections.Generic.List[string]
    if ($NgrokReady) { $ProviderOrder.Add("ngrok") }
    if ($TailscaleReady) { $ProviderOrder.Add("tailscale") }
    $ProviderOrder.Add("cloudflare")
    if (-not $NgrokReady -and $NgrokAuthToken) { $ProviderOrder.Insert(0, "ngrok") }
    if (-not $TailscaleReady -and $LoginIfNeeded) { $ProviderOrder.Add("tailscale") }
} else {
    $ProviderOrder = @($Provider)
}

foreach ($CandidateProvider in $ProviderOrder) {
    foreach ($Route in $Routes) {
        if ($CandidateProvider -eq "tailscale" -and $Route.mode -eq "proxy") {
            continue
        }
        try {
            & (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
            $Result = $null
            if ($CandidateProvider -eq "ngrok") {
                if (-not $NgrokReady -and -not $NgrokAuthToken) {
                    throw "ngrok is not configured. Run scripts/setup-ngrok.ps1 once."
                }
                $Arguments = @{
                    Port = $Port
                    ProxyUrl = [string]$Route.proxy_url
                    Restart = $true
                    InstallIfMissing = $InstallIfMissing
                }
                if ($NgrokAuthToken) { $Arguments.AuthToken = $NgrokAuthToken }
                $Result = & (Join-Path $PSScriptRoot "start-ngrok-tunnel.ps1") @Arguments | ConvertFrom-Json
            } elseif ($CandidateProvider -eq "tailscale") {
                $Result = & (Join-Path $PSScriptRoot "start-tailscale-funnel.ps1") `
                    -Port $Port `
                    -Restart `
                    -InstallIfMissing:$InstallIfMissing `
                    -LoginIfNeeded:$LoginIfNeeded | ConvertFrom-Json
            } else {
                $Result = & (Join-Path $PSScriptRoot "start-quick-tunnel.ps1") `
                    -Port $Port `
                    -ProxyUrl ([string]$Route.proxy_url) `
                    -Restart `
                    -InstallIfMissing:$InstallIfMissing | ConvertFrom-Json
            }
            if (-not $Result.url) { throw "Provider returned no public URL." }
            & (Join-Path $PSScriptRoot "test-public-endpoint.ps1") -PublicBaseUrl $Result.url | Out-Null
            $StatePath = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tunnel.json"
            $State = [ordered]@{
                provider = $Result.provider
                pid = $Result.pid
                url = $Result.url
                local_url = "http://127.0.0.1:$Port"
                healthy = $true
                network_mode = $Route.mode
                proxy_url = Get-SafeProxyUrl ([string]$Route.proxy_url)
                route_source = $Route.source
                stable_url = ($Result.provider -in @("ngrok", "tailscale-funnel"))
                started_at = (Get-Date).ToUniversalTime().ToString("o")
                provider_state = $Result
                network_profile = $Network
                provider_availability = @{
                    ngrok_configured = $NgrokReady
                    tailscale_running = $TailscaleReady
                }
            }
            $State | ConvertTo-Json -Depth 12 | Set-Content $StatePath -Encoding UTF8
            $State | ConvertTo-Json -Depth 12
            exit 0
        } catch {
            $Attempts.Add([pscustomobject]@{
                provider = $CandidateProvider
                route = $Route.mode
                proxy_url = Get-SafeProxyUrl ([string]$Route.proxy_url)
                error = $_.Exception.Message
            })
        }
    }
}

& (Join-Path $PSScriptRoot "stop-tunnel.ps1") | Out-Null
$Summary = $Attempts | ConvertTo-Json -Depth 8
throw "No tunnel provider could establish a healthy public endpoint. Attempts: $Summary"
