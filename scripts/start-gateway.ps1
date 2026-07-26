param(
    [int]$Port = 8766,
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$IUnderstand,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$StatePath = Join-Path $StateDir "gateway.json"
$OutLog = Join-Path $StateDir "gateway.stdout.log"
$ErrLog = Join-Path $StateDir "gateway.stderr.log"

function Get-GatewayHealth {
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
    } catch {
        return $null
    }
}

$Existing = Get-GatewayHealth
if ($Existing -and -not $Restart) {
    $Existing | ConvertTo-Json -Depth 5
    exit 0
}
if ($Restart) {
    & (Join-Path $PSScriptRoot "stop-gateway.ps1") -Port $Port -ErrorAction SilentlyContinue
}
if ($FullAccess -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand."
}

$RunScript = Join-Path $PSScriptRoot "run-actions.ps1"
$Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $RunScript),
    "-Port", "$Port"
)
if ($FullAccess) { $Arguments += @("-FullAccess", "-IUnderstand") }
if ($Autonomous) { $Arguments += "-Autonomous" }

Remove-Item $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue
$Process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList ($Arguments -join " ") `
    -WorkingDirectory $RepoRoot `
    -WindowStyle Minimized `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -PassThru

$Deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Milliseconds 500
    $Health = Get-GatewayHealth
    if ($Health) {
        [ordered]@{
            pid = $Process.Id
            port = $Port
            profile = $(if ($FullAccess) { "full" } else { "safe" })
            approval_policy = $(if ($Autonomous) { "autonomous" } else { "guarded" })
            started_at = (Get-Date).ToUniversalTime().ToString("o")
            stdout_log = $OutLog
            stderr_log = $ErrLog
        } | ConvertTo-Json | Set-Content -Path $StatePath -Encoding UTF8
        $Health | Add-Member -NotePropertyName pid -NotePropertyValue $Process.Id -Force
        $Health | Add-Member -NotePropertyName stdout_log -NotePropertyValue $OutLog -Force
        $Health | Add-Member -NotePropertyName stderr_log -NotePropertyValue $ErrLog -Force
        $Health | ConvertTo-Json -Depth 5
        exit 0
    }
    if ($Process.HasExited) {
        $ErrorText = if (Test-Path $ErrLog) { Get-Content $ErrLog -Raw } else { "" }
        throw "Gateway exited before becoming healthy. Exit code: $($Process.ExitCode). $ErrorText"
    }
} while ((Get-Date) -lt $Deadline)

try { & taskkill.exe /PID $Process.Id /T /F | Out-Null } catch {}
throw "Gateway did not become healthy within 45 seconds. Inspect $ErrLog"
