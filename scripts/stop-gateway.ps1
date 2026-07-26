param([int]$Port = 8766)

$ErrorActionPreference = "Continue"
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$Connections = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
$Pids = @($Connections | Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($ProcessId in $Pids) {
    if ($ProcessId -and $ProcessId -ne $PID) {
        & taskkill.exe /PID $ProcessId /T /F | Out-Null
    }
}
Remove-Item (Join-Path $StateDir "gateway.json") -Force -ErrorAction SilentlyContinue
[ordered]@{ stopped = $true; port = $Port; process_ids = $Pids } | ConvertTo-Json
