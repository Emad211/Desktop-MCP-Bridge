param(
    [string]$TaskName = "Desktop MCP Bridge Tunnel Supervisor",
    [ValidateSet("auto", "ngrok", "cloudflare", "tailscale")]
    [string]$Provider = "auto",
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [switch]$InstallIfMissing,
    [switch]$LoginIfNeeded,
    [switch]$AllowEphemeral,
    [switch]$StartNow
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SupervisorScript = Join-Path $RepoRoot "scripts\start-tunnel-supervisor.ps1"
$Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$SupervisorScript`" -Provider $Provider -NetworkMode $NetworkMode -Restart"
if ($InstallIfMissing) { $Arguments += " -InstallIfMissing" }
if ($LoginIfNeeded) { $Arguments += " -LoginIfNeeded" }
if ($AllowEphemeral) { $Arguments += " -AllowEphemeral" }

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $Arguments `
    -WorkingDirectory $RepoRoot
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 20 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force | Out-Null
Write-Host "Tunnel supervisor autostart installed: $TaskName" -ForegroundColor Green
if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Tunnel supervisor autostart task started." -ForegroundColor Cyan
}
