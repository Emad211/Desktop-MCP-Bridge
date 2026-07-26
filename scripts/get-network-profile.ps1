param(
    [string]$ProbeUrl = "https://api.ipify.org?format=json",
    [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "SilentlyContinue"
$ProxyCandidates = New-Object System.Collections.Generic.List[object]
$Seen = @{}

function Add-ProxyCandidate {
    param([string]$Url, [string]$Source)
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    $Normalized = $Url.Trim()
    if ($Normalized -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $Normalized = "http://$Normalized"
    }
    if ($Seen.ContainsKey($Normalized.ToLowerInvariant())) { return }
    $Seen[$Normalized.ToLowerInvariant()] = $true
    $Uri = $null
    try { $Uri = [uri]$Normalized } catch { return }
    if (-not $Uri.Host -or -not $Uri.Port) { return }
    $Listening = $false
    try {
        $Listening = Test-NetConnection -ComputerName $Uri.Host -Port $Uri.Port -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {}
    $ProxyCandidates.Add([pscustomobject]@{
        url = $Normalized
        source = $Source
        scheme = $Uri.Scheme
        host = $Uri.Host
        port = $Uri.Port
        listening = [bool]$Listening
    })
}

foreach ($Name in @("ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")) {
    $Value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $Value) { $Value = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $Value) { $Value = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    if ($Value) { Add-ProxyCandidate -Url $Value -Source "environment:$Name" }
}

try {
    $InternetSettings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($InternetSettings.ProxyEnable -eq 1 -and $InternetSettings.ProxyServer) {
        $ProxyServer = [string]$InternetSettings.ProxyServer
        if ($ProxyServer -match '=') {
            foreach ($Part in $ProxyServer -split ';') {
                if ($Part -match '^(?<scheme>https?|socks|socks5)=(?<address>.+)$') {
                    $Scheme = $Matches.scheme
                    if ($Scheme -eq 'socks') { $Scheme = 'socks5' }
                    Add-ProxyCandidate -Url "$Scheme://$($Matches.address)" -Source "wininet:$($Matches.scheme)"
                }
            }
        } else {
            Add-ProxyCandidate -Url $ProxyServer -Source "wininet"
        }
    }
    $PacUrl = [string]$InternetSettings.AutoConfigURL
} catch {
    $PacUrl = $null
}

$WinHttpOutput = (& netsh winhttp show proxy 2>&1 | Out-String)
if ($WinHttpOutput -match 'Proxy Server\(s\)\s*:\s*(?<proxy>[^\r\n]+)') {
    $ProxyText = $Matches.proxy.Trim()
    foreach ($Part in $ProxyText -split ';') {
        if ($Part -match '^(?<scheme>https?|socks|socks5)=(?<address>.+)$') {
            $Scheme = $Matches.scheme
            if ($Scheme -eq 'socks') { $Scheme = 'socks5' }
            Add-ProxyCandidate -Url "$Scheme://$($Matches.address)" -Source "winhttp:$($Matches.scheme)"
        } else {
            Add-ProxyCandidate -Url $Part -Source "winhttp"
        }
    }
}

$LoopbackPorts = @(10808, 10809, 1080, 1081, 2080, 2081, 7890, 7891, 7897, 8080, 8888)
foreach ($Port in $LoopbackPorts) {
    $Listening = $false
    try {
        $Listening = Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {}
    if (-not $Listening) { continue }
    $Scheme = if ($Port -in @(10808, 1080, 1081, 7891)) { "socks5" } else { "http" }
    Add-ProxyCandidate -Url "$Scheme://127.0.0.1:$Port" -Source "loopback-scan"
}

function Invoke-CurlProbe {
    param([string]$ProxyUrl)
    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $Curl) { return $null }
    $Arguments = @("--silent", "--show-error", "--location", "--max-time", "$TimeoutSeconds", "--output", "NUL", "--write-out", "%{http_code}")
    if ($ProxyUrl) { $Arguments += @("--proxy", $ProxyUrl) }
    $Arguments += $ProbeUrl
    $Output = & $Curl.Source @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    return [pscustomobject]@{
        success = ($ExitCode -eq 0 -and ([string]$Output -match '^[123][0-9][0-9]$'))
        exit_code = $ExitCode
        http_code = [string]$Output
    }
}

$DirectProbe = Invoke-CurlProbe -ProxyUrl $null
foreach ($Candidate in $ProxyCandidates) {
    if ($Candidate.listening) {
        $Candidate | Add-Member -NotePropertyName probe -NotePropertyValue (Invoke-CurlProbe -ProxyUrl $Candidate.url)
    } else {
        $Candidate | Add-Member -NotePropertyName probe -NotePropertyValue $null
    }
}

$WorkingProxies = @($ProxyCandidates | Where-Object { $_.probe -and $_.probe.success })
$LikelyV2Ray = @($ProxyCandidates | Where-Object {
    $_.host -in @("127.0.0.1", "localhost", "::1") -and $_.listening
}).Count -gt 0

[ordered]@{
    vpn_or_tun_likely_active = [bool]($DirectProbe -and $DirectProbe.success -and $LikelyV2Ray)
    direct_probe = $DirectProbe
    pac_url = $PacUrl
    winhttp = $WinHttpOutput.Trim()
    proxy_candidates = @($ProxyCandidates)
    working_proxies = $WorkingProxies
    recommended_mode = $(if ($DirectProbe -and $DirectProbe.success) { "direct-first" } elseif ($WorkingProxies.Count -gt 0) { "proxy" } else { "offline-or-blocked" })
    detected_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 10
