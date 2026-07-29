param(
    [string]$AuthToken = $env:NGROK_AUTHTOKEN,
    [int]$Port = 8766,
    [switch]$InstallIfMissing,
    [switch]$StartTunnel,
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto"
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) {
    if (-not $InstallIfMissing) {
        throw "ngrok is not installed. Re-run with -InstallIfMissing."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required for automatic ngrok installation."
    }
    & winget install --id Ngrok.Ngrok --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "ngrok installation failed: $LASTEXITCODE" }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
$Ngrok = (Get-Command ngrok -ErrorAction Stop).Source

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    throw "An ngrok authtoken is required once. Create a free ngrok account, copy its authtoken, set it only for this PowerShell process with `$env:NGROK_AUTHTOKEN='<token>', then rerun this script."
}

& $Ngrok config add-authtoken $AuthToken | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ngrok rejected the supplied authtoken." }
$Check = & $Ngrok config check 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "ngrok config validation failed: $Check" }

$Result = [ordered]@{
    configured = $true
    config_check = $Check.Trim()
    stable_development_domain = $true
    token_stored_by_ngrok = $true
    token_written_to_project = $false
}
if ($StartTunnel) {
    $Tunnel = & (Join-Path $PSScriptRoot "start-tunnel.ps1") `
        -Provider ngrok `
        -NetworkMode $NetworkMode `
        -Port $Port `
        -NgrokAuthToken $AuthToken `
        -Restart | ConvertFrom-Json
    $Result.tunnel = $Tunnel
    $Result.gpt_config = & (Join-Path $PSScriptRoot "export-gpt-config.ps1") -PublicBaseUrl $Tunnel.url | ConvertFrom-Json
}
$Result | ConvertTo-Json -Depth 15
