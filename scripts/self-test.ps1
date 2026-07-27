param(
    [string]$BaseUrl = "http://127.0.0.1:8766",
    [string]$EncryptedKeyPath = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml"),
    [switch]$SkipBrowser,
    [switch]$SkipOCR
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $EncryptedKeyPath)) { throw "Encrypted Action key missing: $EncryptedKeyPath" }
$Credential = Import-Clixml -Path $EncryptedKeyPath
$Key = $Credential.GetNetworkCredential().Password
$Headers = @{ Authorization = "Bearer $Key" }
$BaseUrl = $BaseUrl.TrimEnd('/')
$Results = [ordered]@{}

function Invoke-Observe([string]$Operation, [hashtable]$Arguments = @{}) {
    $Body = @{ operation = $Operation; arguments = $Arguments } | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method Post -Uri "$BaseUrl/v1/observe" -Headers $Headers -ContentType "application/json" -Body $Body -TimeoutSec 40
}
function Invoke-Act([string]$Operation, [hashtable]$Arguments = @{}, [switch]$Confirm) {
    $Payload = @{ operation = $Operation; arguments = $Arguments; request_id = [guid]::NewGuid().ToString() }
    if ($Confirm) { $Payload.confirmation = "CONFIRM:$Operation" }
    return Invoke-RestMethod -Method Post -Uri "$BaseUrl/v1/act" -Headers $Headers -ContentType "application/json" -Body ($Payload | ConvertTo-Json -Depth 20) -TimeoutSec 40
}

$Results.health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 10
$Results.status = Invoke-Observe "status"
$ScreenshotPath = Join-Path $env:TEMP "desktop-mcp-self-test.png"
Invoke-WebRequest -Uri "$BaseUrl/v1/screenshot?monitor=1&max_width=1280" -Headers $Headers -OutFile $ScreenshotPath -TimeoutSec 30
$Results.screenshot = @{ path = $ScreenshotPath; bytes = (Get-Item $ScreenshotPath).Length }
if ($Results.screenshot.bytes -lt 1000) { throw "Screenshot self-test returned an unexpectedly small file." }

if (-not $SkipOCR) {
    $Results.ocr = Invoke-Observe "screen_ocr" @{ monitor = 1; language = "eng+fas"; include_image = $false; min_confidence = 20 }
}
if (-not $SkipBrowser) {
    $ExpectedTitle = "Desktop MCP Bridge Self Test"
    $Html = '<!doctype html><html><head><meta charset="utf-8"><title>Desktop MCP Bridge Self Test</title></head><body><main><h1>Desktop MCP Bridge Browser Ready</h1><button type="button">Self Test Button</button></main></body></html>'
    $DataUrl = "data:text/html;charset=utf-8,$([uri]::EscapeDataString($Html))"

    $Results.browser_start = Invoke-Act "browser_start" @{ headless = $false }
    $Results.browser_test_tab = Invoke-Act "browser_tabs" @{ tab_operation = "new" }
    $Results.browser_navigate = Invoke-Act "browser_navigate" @{ url = $DataUrl; wait_until = "domcontentloaded"; timeout_seconds = 30 }

    $BrowserReady = $false
    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        $Results.browser_snapshot = Invoke-Observe "browser_snapshot" @{ max_chars = 20000 }
        $Snapshot = $Results.browser_snapshot.result
        if (
            $Snapshot.title -eq $ExpectedTitle -and
            $Snapshot.url -like "data:text/html*"
        ) {
            $BrowserReady = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $BrowserReady) {
        $Navigate = $Results.browser_navigate.result
        $Snapshot = $Results.browser_snapshot.result
        $Backend = $Results.browser_start.result.backend
        throw (
            "Browser self-test did not reach its isolated local page. " +
            "navigate_url='$($Navigate.url)', navigate_title='$($Navigate.title)', " +
            "snapshot_url='$($Snapshot.url)', snapshot_title='$($Snapshot.title)', " +
            "backend='$($Backend.label)'."
        )
    }

    $Results.browser_close_test_tab = Invoke-Act "browser_tabs" @{ tab_operation = "close" }
}

$Job = Invoke-Act "start_command_job" @{ command = "cmd /d /c echo Desktop-MCP-Bridge-Self-Test" } -Confirm
$JobId = $Job.result.id
if (-not $JobId) { throw "Command job did not return a job_id." }
for ($Index = 0; $Index -lt 30; $Index++) {
    Start-Sleep -Milliseconds 500
    $JobResult = Invoke-Observe "get_command_job" @{ job_id = $JobId; tail_bytes = 10000 }
    if ($JobResult.result.status -in @("completed", "failed", "cancelled")) { break }
}
$Results.command_job = $JobResult
if ($JobResult.result.status -ne "completed" -or $JobResult.result.stdout -notmatch "Desktop-MCP-Bridge-Self-Test") {
    throw "Command job self-test failed."
}
$Results.ok = $true
$Results | ConvertTo-Json -Depth 20
