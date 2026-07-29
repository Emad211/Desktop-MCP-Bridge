param(
    [string]$TaskName = "Desktop MCP Bridge Action Gateway",
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$IUnderstand,
    [switch]$StartNow
)

$ErrorActionPreference = "Stop"
if ($FullAccess -and -not $IUnderstand) { throw "Full access autostart requires -IUnderstand." }
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StartScript = Join-Path $RepoRoot "scripts\start-gateway.ps1"
$Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$StartScript`" -Restart"
if ($FullAccess) { $Arguments += " -FullAccess -RequireAdministrator -IUnderstand" }
if ($Autonomous) { $Arguments += " -Autonomous" }

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Arguments -WorkingDirectory $RepoRoot
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
Write-Host "Verified gateway autostart task installed: $TaskName" -ForegroundColor Green
if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Autostart task started." -ForegroundColor Cyan
}
