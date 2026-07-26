param(
    [ValidateSet("auto", "ngrok", "cloudflare", "tailscale")]
    [string]$Provider = "auto",
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [int]$Port = 8766,
    [string]$NgrokAuthToken = $env:NGROK_AUTHTOKEN,
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$AllowEphemeral,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "tunnel-supervisor.json"
$OutLog = Join-Path $StateDir "tunnel-supervisor.stdout.log"
$ErrLog = Join-Path $StateDir "tunnel-supervisor.stderr.log"

if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-tunnel-supervisor.ps1") -StopTunnel | Out-Null
}
if (Test-Path $StatePath) {
    try {
        $Existing = Get-Content $StatePath -Raw | ConvertFrom-Json
        if ($Existing.pid -and (Get-Process -Id $Existing.pid -ErrorAction SilentlyContinue)) {
            $Existing | ConvertTo-Json -Depth 6
            exit 0
        }
    } catch {}
}

$SupervisorScript = Join-Path $PSScriptRoot "tunnel-supervisor.ps1"
$Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $SupervisorScript),
    "-Provider", $Provider,
    "-NetworkMode", $NetworkMode,
    "-Port", "$Port"
)
if ($InstallIfMissing) { $Arguments += "-InstallIfMissing" }
if ($LoginIfNeeded) { $Arguments += "-LoginIfNeeded" }
if ($AllowEphemeral) { $Arguments += "-AllowEphemeral" }

$PreviousToken = [Environment]::GetEnvironmentVariable("NGROK_AUTHTOKEN", "Process")
if ($NgrokAuthToken) {
    [Environment]::SetEnvironmentVariable("NGROK_AUTHTOKEN", $NgrokAuthToken, "Process")
}
try {
    Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
    $Process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList ($Arguments -join " ") `
        -WindowStyle Minimized `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru
} finally {
    [Environment]::SetEnvironmentVariable("NGROK_AUTHTOKEN", $PreviousToken, "Process")
}

$Deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 500
    if (Test-Path $StatePath) {
        try {
            $State = Get-Content $StatePath -Raw | ConvertFrom-Json
            if ($State.pid -eq $Process.Id -and $State.status -eq "running") {
                $State | Add-Member -NotePropertyName stdout_log -NotePropertyValue $OutLog -Force
                $State | Add-Member -NotePropertyName stderr_log -NotePropertyValue $ErrLog -Force
                $State | ConvertTo-Json -Depth 6
                exit 0
            }
        } catch {}
    }
    if ($Process.HasExited) {
        $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "Tunnel supervisor exited during startup. $ErrorText"
    }
} while ((Get-Date) -lt $Deadline)

try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
throw "Tunnel supervisor did not initialize within 20 seconds. Inspect $ErrLog"
