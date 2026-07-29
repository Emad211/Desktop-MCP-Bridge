param(
    [string]$RepairRunId = "",
    [string]$ProgressPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\repair-progress.json"),
    [string]$ReportPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\repair-report.json")
)

$ErrorActionPreference = "Stop"
$Result = [ordered]@{
    found = $false
    repair_run_id = $RepairRunId
    progress_path = $ProgressPath
    report_path = $ReportPath
    progress = $null
    report = $null
    terminal = $false
}

if (Test-Path $ProgressPath) {
    try {
        $Progress = Get-Content $ProgressPath -Raw | ConvertFrom-Json
        if (-not $RepairRunId -or $Progress.repair_run_id -eq $RepairRunId) {
            $Result.found = $true
            $Result.repair_run_id = [string]$Progress.repair_run_id
            $Result.progress = $Progress
            $Result.terminal = $Progress.status -in @("completed", "failed", "cancelled")
            foreach ($Name in @("broker_pid", "repair_pid")) {
                if ($Progress.$Name) {
                    $Result["${Name}_running"] = [bool](Get-Process -Id ([int]$Progress.$Name) -ErrorAction SilentlyContinue)
                }
            }
        }
    } catch {
        $Result.progress_error = $_.Exception.Message
    }
}
if (Test-Path $ReportPath) {
    try {
        $Report = Get-Content $ReportPath -Raw | ConvertFrom-Json
        if (-not $RepairRunId -or $Report.repair_run_id -eq $RepairRunId) {
            $Result.report = $Report
            if ($Report.ok -eq $true) { $Result.terminal = $true }
        }
    } catch {
        $Result.report_error = $_.Exception.Message
    }
}

$Result | ConvertTo-Json -Depth 30
