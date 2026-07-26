param(
    [string[]]$TaskName = @(
        "Desktop MCP Bridge Action Gateway",
        "Desktop MCP Bridge Tunnel Supervisor"
    )
)

$ErrorActionPreference = "Stop"
$Results = @()
foreach ($Name in $TaskName) {
    $Existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($Existing) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
        $Results += [pscustomobject]@{ task_name = $Name; removed = $true }
        Write-Host "Autostart task removed: $Name" -ForegroundColor Green
    } else {
        $Results += [pscustomobject]@{ task_name = $Name; removed = $false }
        Write-Host "Autostart task was not installed: $Name" -ForegroundColor Yellow
    }
}
$Results | ConvertTo-Json -Depth 5
