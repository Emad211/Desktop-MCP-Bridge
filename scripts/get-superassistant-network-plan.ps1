param(
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [string]$ProxyUrl = "",
    [string]$ProbeUrl = "https://registry.npmjs.org/@srbhptl39%2fmcp-superassistant-proxy",
    [int]$TimeoutSeconds = 12
)

$ErrorActionPreference = "Stop"
$LocalBypass = "localhost,127.0.0.1,::1"

function Invoke-RouteProbe {
    param(
        [string]$Url,
        [string]$RouteProxy = "",
        [switch]$ForceDirect
    )
    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $Curl) {
        return [ordered]@{
            success = $false
            exit_code = -1
            http_code = ""
            error = "curl.exe was not found"
        }
    }

    $Arguments = @(
        "--silent",
        "--show-error",
        "--location",
        "--max-time", "$TimeoutSeconds",
        "--output", "NUL",
        "--write-out", "%{http_code}"
    )
    if ($ForceDirect) {
        $Arguments += @("--noproxy", "*")
    } elseif ($RouteProxy) {
        $Arguments += @("--proxy", $RouteProxy)
    }
    $Arguments += $Url

    $Output = & $Curl.Source @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $HttpCode = [string]$Output
    [ordered]@{
        success = ($ExitCode -eq 0 -and $HttpCode -match '^[123][0-9][0-9]$')
        exit_code = $ExitCode
        http_code = $HttpCode
        error = $(if ($ExitCode -eq 0) { $null } else { $HttpCode })
    }
}

$ProfileRaw = & (Join-Path $PSScriptRoot "get-network-profile.ps1") `
    -ProbeUrl $ProbeUrl `
    -TimeoutSeconds $TimeoutSeconds
$Profile = $ProfileRaw | ConvertFrom-Json

$ExplicitProxy = $null
if ($ProxyUrl) {
    try {
        $Uri = [uri]$ProxyUrl
        if ($Uri.UserInfo) {
            throw "Credential-bearing proxy URLs are not accepted."
        }
        if ($Uri.Scheme -notin @("http", "https")) {
            throw "The Node/npm path requires an HTTP or HTTPS proxy URL."
        }
        $ExplicitProxy = $Uri.AbsoluteUri.TrimEnd('/')
    } catch {
        throw "Invalid -ProxyUrl: $($_.Exception.Message)"
    }
}

$WorkingHttpProxies = @(
    $Profile.working_proxies |
        Where-Object { $_.scheme -in @("http", "https") } |
        ForEach-Object { $_ }
)
$CandidateProxy = if ($ExplicitProxy) {
    $ExplicitProxy
} elseif ($WorkingHttpProxies.Count -gt 0) {
    [string]$WorkingHttpProxies[0].url
} else {
    $null
}

$DirectProbe = Invoke-RouteProbe -Url $ProbeUrl -ForceDirect
$ProxyProbe = if ($CandidateProxy) {
    Invoke-RouteProbe -Url $ProbeUrl -RouteProxy $CandidateProxy
} else {
    $null
}

$ResolvedMode = "offline-or-blocked"
$SelectedProxy = $null
switch ($NetworkMode) {
    "direct" {
        if ($DirectProbe.success) {
            $ResolvedMode = "direct"
        }
    }
    "proxy" {
        if (-not $CandidateProxy) {
            throw "Proxy mode was requested, but no working HTTP/HTTPS proxy was supplied or detected."
        }
        if ($ProxyProbe.success) {
            $ResolvedMode = "proxy"
            $SelectedProxy = $CandidateProxy
        }
    }
    "auto" {
        if ($DirectProbe.success) {
            $ResolvedMode = "direct"
        } elseif ($CandidateProxy -and $ProxyProbe.success) {
            $ResolvedMode = "proxy"
            $SelectedProxy = $CandidateProxy
        }
    }
}

$BootstrapInstruction = switch ($ResolvedMode) {
    "direct" { "The current route can reach npm. Keep the current VPN state for proxy bootstrap." }
    "proxy" { "Use the detected HTTP proxy for npm bootstrap. Keep the VPN/V2Ray process running." }
    default { "Turn the VPN/V2Ray on, confirm an HTTP proxy or TUN route is active, then rerun the command." }
}

[ordered]@{
    ok = ($ResolvedMode -ne "offline-or-blocked")
    requested_mode = $NetworkMode
    resolved_mode = $ResolvedMode
    selected_proxy = $SelectedProxy
    local_bypass = $LocalBypass
    vpn_or_tun_likely_active = [bool]$Profile.vpn_or_tun_likely_active
    npm_probe_url = $ProbeUrl
    direct_npm_probe = $DirectProbe
    proxy_npm_probe = $ProxyProbe
    detected_http_proxies = @($WorkingHttpProxies | ForEach-Object {
        [ordered]@{
            url = $_.url
            source = $_.source
            host = $_.host
            port = $_.port
        }
    })
    bootstrap_instruction = $BootstrapInstruction
    vpn_policy = [ordered]@{
        dependency_downloads = "VPN on when direct_npm_probe is false; otherwise the current route is acceptable."
        chatgpt_web = "Keep VPN on whenever it is required to open and use chatgpt.com."
        localhost_proxy = "VPN may be on or off; localhost, 127.0.0.1, and ::1 are always bypassed."
        first_gate_c_test = "Keep VPN on for the entire first ChatGPT acceptance test to remove one variable."
        resilience_toggle = "Only toggle VPN after Gate C passes; test localhost status while off, then turn it on before returning to ChatGPT."
    }
    raw_network_profile = $Profile
    detected_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 20
