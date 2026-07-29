param(
    [int]$Port = 8766,
    [int]$WaitSeconds = 15
)

$ErrorActionPreference = "Stop"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$Attempts = New-Object System.Collections.Generic.List[object]
$Connections = @(Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$ProcessIds = @($Connections | Select-Object -ExpandProperty OwningProcess -Unique)

foreach ($ProcessId in $ProcessIds) {
    if (-not $ProcessId -or $ProcessId -eq $PID) { continue }
    $Output = @(& taskkill.exe /PID $ProcessId /T /F 2>&1)
    $Attempts.Add([pscustomobject]@{
        process_id = $ProcessId
        exit_code = $LASTEXITCODE
        output = ($Output | Out-String).Trim()
    })
}

$Deadline = (Get-Date).AddSeconds([math]::Max(1, $WaitSeconds))
do {
    Start-Sleep -Milliseconds 250
    $Remaining = @(Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($Remaining.Count -eq 0) { break }
} while ((Get-Date) -lt $Deadline)

$RemainingProcessIds = @($Remaining | Select-Object -ExpandProperty OwningProcess -Unique)
if ($RemainingProcessIds.Count -gt 0) {
    $Details = $Attempts | ConvertTo-Json -Depth 6 -Compress
    throw "Gateway listener could not be stopped on port $Port. Remaining PIDs: $($RemainingProcessIds -join ', '). Attempts: $Details"
}

Remove-Item (Join-Path $StateDir "gateway.json") -Force -ErrorAction SilentlyContinue
[ordered]@{
    stopped = $true
    port = $Port
    previous_process_ids = $ProcessIds
    attempts = @($Attempts.ToArray())
    remaining_process_ids = @()
} | ConvertTo-Json -Depth 8
