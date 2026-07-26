param([string]$TaskName = "Desktop MCP Bridge Action Gateway")
$ErrorActionPreference = "Stop"
$Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Autostart task removed: $TaskName" -ForegroundColor Green
} else {
    Write-Host "Autostart task was not installed." -ForegroundColor Yellow
}
