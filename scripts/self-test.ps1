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

function Assert-BridgeSuccess {
    param(
        [Parameter(Mandatory=$true)]
        $Response,
        [Parameter(Mandatory=$true)]
        [string]$Label
    )
    if ($null -eq $Response) {
        throw "$Label returned no response."
    }
    if ($Response.ok -ne $true) {
        $Rendered = $Response | ConvertTo-Json -Depth 30 -Compress
        throw "$Label failed: $Rendered"
    }
    return $Response
}

$Results.health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 10
$Results.status = Assert-BridgeSuccess -Response (Invoke-Observe "status") -Label "status"
$ScreenshotPath = Join-Path $env:TEMP "desktop-mcp-self-test.png"
Invoke-WebRequest -Uri "$BaseUrl/v1/screenshot?monitor=1&max_width=1280" -Headers $Headers -OutFile $ScreenshotPath -TimeoutSec 30
$Results.screenshot = @{ path = $ScreenshotPath; bytes = (Get-Item $ScreenshotPath).Length }
if ($Results.screenshot.bytes -lt 1000) { throw "Screenshot self-test returned an unexpectedly small file." }

if (-not $SkipOCR) {
    $Results.ocr = Assert-BridgeSuccess `
        -Response (Invoke-Observe "screen_ocr" @{ monitor = 1; language = "eng+fas"; include_image = $false; min_confidence = 20 }) `
        -Label "screen_ocr"
}

if (-not $SkipBrowser) {
    $ExpectedTitle = "Desktop MCP Bridge Self Test"
    $ExpectedMarker = "Desktop MCP Bridge Browser Ready"
    $TestTabCreated = $false

    try {
        $Results.browser_start = Assert-BridgeSuccess `
            -Response (Invoke-Act "browser_start" @{ headless = $false }) `
            -Label "browser_start"

        $Results.browser_test_tab = Assert-BridgeSuccess `
            -Response (Invoke-Act "browser_tabs" @{ tab_operation = "new" }) `
            -Label "browser_tabs:new"
        $TestTabCreated = $true

        $Results.browser_tabs_after_create = Assert-BridgeSuccess `
            -Response (Invoke-Act "browser_tabs" @{ tab_operation = "list" }) `
            -Label "browser_tabs:list"

        $Results.browser_navigate = Assert-BridgeSuccess `
            -Response (Invoke-Act "browser_navigate" @{ url = "about:blank"; wait_until = "domcontentloaded"; timeout_seconds = 30 }) `
            -Label "browser_navigate:about:blank"

        $Expression = @'
() => {
  document.title = "Desktop MCP Bridge Self Test";
  document.body.innerHTML = '<main><h1 id="dmb-self-test-marker">Desktop MCP Bridge Browser Ready</h1><button type="button">Self Test Button</button></main>';
  return {
    title: document.title,
    marker: document.getElementById("dmb-self-test-marker")?.textContent || "",
    url: location.href
  };
}
'@

        $Results.browser_evaluate = Assert-BridgeSuccess `
            -Response (Invoke-Act "browser_evaluate" @{ expression = $Expression }) `
            -Label "browser_evaluate:self-test-page"

        $Evaluated = $Results.browser_evaluate.result.value
        if ($Evaluated.title -ne $ExpectedTitle -or $Evaluated.marker -ne $ExpectedMarker) {
            $Rendered = $Results.browser_evaluate | ConvertTo-Json -Depth 30 -Compress
            throw "browser_evaluate did not create the expected local page: $Rendered"
        }

        $BrowserReady = $false
        for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
            $Results.browser_snapshot = Assert-BridgeSuccess `
                -Response (Invoke-Observe "browser_snapshot" @{ max_chars = 20000 }) `
                -Label "browser_snapshot"

            $Snapshot = $Results.browser_snapshot.result
            $MarkerFound = $false
            if ([string]$Snapshot.aria_snapshot -match [regex]::Escape($ExpectedMarker)) {
                $MarkerFound = $true
            }
            if (-not $MarkerFound) {
                foreach ($Element in @($Snapshot.interactive_elements)) {
                    if ([string]$Element.text -match "Self Test Button") {
                        $MarkerFound = $true
                        break
                    }
                }
            }

            if ($Snapshot.title -eq $ExpectedTitle -and $MarkerFound) {
                $BrowserReady = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }

        if (-not $BrowserReady) {
            $Failure = [ordered]@{
                browser_start = $Results.browser_start
                browser_test_tab = $Results.browser_test_tab
                browser_tabs_after_create = $Results.browser_tabs_after_create
                browser_navigate = $Results.browser_navigate
                browser_evaluate = $Results.browser_evaluate
                browser_snapshot = $Results.browser_snapshot
            }
            throw "Browser self-test did not observe its isolated local page. Details: $($Failure | ConvertTo-Json -Depth 30 -Compress)"
        }
    }
    finally {
        if ($TestTabCreated) {
            try {
                $Results.browser_close_test_tab = Assert-BridgeSuccess `
                    -Response (Invoke-Act "browser_tabs" @{ tab_operation = "close" }) `
                    -Label "browser_tabs:close"
            }
            catch {
                $Results.browser_cleanup_error = $_.Exception.Message
            }
        }
    }
}

$Job = Assert-BridgeSuccess `
    -Response (Invoke-Act "start_command_job" @{ command = "cmd /d /c echo Desktop-MCP-Bridge-Self-Test" } -Confirm) `
    -Label "start_command_job"
$JobId = $Job.result.id
if (-not $JobId) { throw "Command job did not return a job_id." }
for ($Index = 0; $Index -lt 30; $Index++) {
    Start-Sleep -Milliseconds 500
    $JobResult = Assert-BridgeSuccess `
        -Response (Invoke-Observe "get_command_job" @{ job_id = $JobId; tail_bytes = 10000 }) `
        -Label "get_command_job"
    if ($JobResult.result.status -in @("completed", "failed", "cancelled")) { break }
}
$Results.command_job = $JobResult
if ($JobResult.result.status -ne "completed" -or $JobResult.result.stdout -notmatch "Desktop-MCP-Bridge-Self-Test") {
    throw "Command job self-test failed: $($JobResult | ConvertTo-Json -Depth 30 -Compress)"
}
$Results.ok = $true
$Results | ConvertTo-Json -Depth 30
