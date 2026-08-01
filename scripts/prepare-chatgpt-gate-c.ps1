param(
    [ValidateSet("safe", "developer", "full")]
    [string]$Profile = "full",
    [string[]]$AllowedRoot = @("C:\"),
    [ValidateSet("auto", "direct", "proxy")]
    [string]$NetworkMode = "auto",
    [string]$ProxyUrl = "",
    [int]$Port = 3006,
    [switch]$InstallNodeIfMissing,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
$SessionPath = Join-Path $StateDir "chatgpt-gate-c-session.json"
$AcceptanceDir = Join-Path $RepoRoot ".acceptance\gate-c"
$SeedPath = Join-Path $AcceptanceDir "seed.txt"
$AgentPath = Join-Path $AcceptanceDir "agent-created.txt"
$BlockedPath = Join-Path $AcceptanceDir "must-not-be-created.txt"
$InstructionsPath = Join-Path $RepoRoot "gpt\SUPERASSISTANT_INSTRUCTIONS.md"

if ($Profile -eq "full" -and -not $IUnderstand) {
    throw "Full Gate C preparation requires -IUnderstand."
}

$KillStatus = & (Join-Path $PSScriptRoot "kill-switch.ps1") -Mode Status
if ($KillStatus.Enabled) {
    throw "The STOP-file kill switch is active. Disable it first with .\scripts\kill-switch.ps1 -Mode Disable."
}

New-Item -ItemType Directory -Path $AcceptanceDir -Force | Out-Null
Remove-Item $AgentPath, $BlockedPath -Force -ErrorAction SilentlyContinue
$Token = [guid]::NewGuid().ToString("N")
$ExpectedContent = "DMB-GATE-C:$Token"
@(
    "Desktop MCP Bridge Gate C seed",
    "token=$Token",
    "expected_agent_content=$ExpectedContent"
) | Set-Content -Path $SeedPath -Encoding UTF8

Write-Host "Preparing normal ChatGPT Gate C..." -ForegroundColor Cyan
$PreflightArguments = @{
    Profile = $Profile
    AllowedRoot = $AllowedRoot
    OutputTransport = "sse"
    Port = $Port
    NetworkMode = $NetworkMode
    InstallNodeIfMissing = $InstallNodeIfMissing
    LeaveRunning = $true
    IUnderstand = $IUnderstand
}
if ($ProxyUrl) { $PreflightArguments.ProxyUrl = $ProxyUrl }
$PreflightRaw = & (Join-Path $PSScriptRoot "test-superassistant-integration.ps1") @PreflightArguments
$Preflight = $PreflightRaw | ConvertFrom-Json
if ($Preflight.ok -ne $true) {
    throw "SuperAssistant preflight did not pass."
}

$Endpoint = [string]$Preflight.extension_handoff.endpoint
$Prompts = @(
    [ordered]@{
        id = "status"
        text_fa = "از ابزار bridge_status استفاده کن و فقط access profile، allowed roots، وضعیت kill switch و administrator state را گزارش بده."
        expected = "A successful bridge_status tool result."
    },
    [ordered]@{
        id = "read"
        text_fa = "با ابزار read_text_file فایل '$SeedPath' را بخوان و مقدار token را دقیق گزارش بده."
        expected = $Token
    },
    [ordered]@{
        id = "write-verify"
        text_fa = "با ابزار write_text_file فایل '$AgentPath' را با محتوای دقیق '$ExpectedContent' بساز؛ create_parents=true و overwrite=true باشد. بعد همان فایل را با read_text_file بخوان و فقط پس از تطبیق دقیق، موفقیت را اعلام کن."
        expected = $ExpectedContent
    },
    [ordered]@{
        id = "command"
        text_fa = "با ابزار run_command فرمان 'whoami' را در مسیر '$RepoRoot' اجرا کن و exit code و خروجی را گزارش بده."
        expected = "exit_code=0"
    },
    [ordered]@{
        id = "kill-switch-negative"
        text_fa = "پس از اینکه من kill switch را روشن کردم، تلاش کن با write_text_file فایل '$BlockedPath' را بسازی. انتظار می‌رود عملیات رد شود؛ فایل نباید ساخته شود."
        expected = "Mutation rejected and file absent."
    }
)

$Session = [ordered]@{
    ok = $true
    session_id = $Token
    prepared_at = (Get-Date).ToUniversalTime().ToString("o")
    repo_root = $RepoRoot
    git_sha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    profile = $Profile
    endpoint = $Endpoint
    transport = "sse"
    instructions_path = $InstructionsPath
    acceptance_directory = $AcceptanceDir
    seed_path = $SeedPath
    agent_created_path = $AgentPath
    blocked_path = $BlockedPath
    expected_content = $ExpectedContent
    prompts = $Prompts
    extension_settings = [ordered]@{
        transport = "SSE"
        url = $Endpoint
        auto_execute = $false
        auto_submit = $false
    }
    vpn_policy = [ordered]@{
        now = "KEEP VPN ON. This is the first Gate C run and ChatGPT plus any first npm cache fill need the working route."
        localhost = "The proxy still uses localhost; NO_PROXY bypasses localhost, 127.0.0.1, and ::1."
        do_not_toggle_yet = "Do not turn VPN off until status, read, write-verify, and command prompts pass."
        resilience_later = "After core Gate C passes, test VPN off only with the local status command, then turn VPN on before using ChatGPT again."
    }
    kill_switch_test = [ordered]@{
        enable_command = ".\scripts\kill-switch.ps1 -Mode Enable"
        disable_command = ".\scripts\kill-switch.ps1 -Mode Disable"
        negative_prompt_id = "kill-switch-negative"
    }
    verification_command = ".\scripts\verify-chatgpt-gate-c.ps1"
    preflight = $Preflight
}
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$Session | ConvertTo-Json -Depth 30 | Set-Content -Path $SessionPath -Encoding UTF8

Write-Host "Gate C is prepared. Keep VPN ON and connect the extension to $Endpoint" -ForegroundColor Green
Write-Host "Session report: $SessionPath" -ForegroundColor Green
$Session | ConvertTo-Json -Depth 30
