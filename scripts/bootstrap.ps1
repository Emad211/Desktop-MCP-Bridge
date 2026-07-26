param(
    [switch]$FullAccess,
    [switch]$Autonomous,
    [switch]$InstallAutostart,
    [switch]$StartNow,
    [switch]$RunSelfTest,
    [switch]$SkipBrowser,
    [switch]$SkipOCR,
    [switch]$RotateKey,
    [switch]$NoAutoElevate,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$InvocationParameters = @{} + $PSBoundParameters
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-SelfElevated {
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath),
        "-NoAutoElevate"
    )
    foreach ($SwitchName in @(
        "FullAccess",
        "Autonomous",
        "InstallAutostart",
        "StartNow",
        "RunSelfTest",
        "SkipBrowser",
        "SkipOCR",
        "RotateKey",
        "IUnderstand"
    )) {
        if ($InvocationParameters.ContainsKey($SwitchName) -and $InvocationParameters[$SwitchName]) {
            $Arguments += "-$SwitchName"
        }
    }
    Write-Host "Administrator rights are required. A UAC confirmation window will open." -ForegroundColor Yellow
    try {
        $Child = Start-Process -FilePath "powershell.exe" `
            -ArgumentList ($Arguments -join " ") `
            -WorkingDirectory $RepoRoot `
            -Verb RunAs `
            -Wait `
            -PassThru
    } catch {
        throw "Unable to start an elevated PowerShell. Approve the UAC prompt and retry. $($_.Exception.Message)"
    }
    exit $Child.ExitCode
}

if ($FullAccess -and -not $IUnderstand) {
    throw "Full access requires -IUnderstand. It grants the bridge all permissions available to this Windows session."
}

$NeedsElevation = $FullAccess -or $InstallAutostart
if ($NeedsElevation -and -not (Test-Administrator)) {
    if ($NoAutoElevate) {
        throw "This operation requires Administrator rights, but the elevated process is still non-admin."
    }
    Invoke-SelfElevated
}

& (Join-Path $PSScriptRoot "install.ps1") `
    -SkipBrowser:$SkipBrowser `
    -SkipOCR:$SkipOCR

$StateDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$EncryptedKeyPath = Join-Path $StateDir "action-key.clixml"
$NewKey = $null
if ($RotateKey -or -not (Test-Path $EncryptedKeyPath)) {
    $NewKey = & (Join-Path $PSScriptRoot "new-action-key.ps1")
    & (Join-Path $PSScriptRoot "save-action-key.ps1") -ApiKey $NewKey
} else {
    Write-Host "Using the existing DPAPI-protected Action key." -ForegroundColor DarkGray
}

$Config = [ordered]@{
    repo_root = $RepoRoot
    profile = $(if ($FullAccess) { "full" } else { "safe" })
    approval_policy = $(if ($Autonomous) { "autonomous" } else { "guarded" })
    action_port = 8766
    administrator = Test-Administrator
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
}
$Config | ConvertTo-Json | Set-Content -Path (Join-Path $StateDir "bootstrap.json") -Encoding UTF8

if ($InstallAutostart) {
    & (Join-Path $PSScriptRoot "install-autostart.ps1") `
        -FullAccess:$FullAccess `
        -Autonomous:$Autonomous `
        -IUnderstand:$IUnderstand
}

Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
if ($NewKey) {
    Write-Host "Action key (shown once; also protected with DPAPI):" -ForegroundColor Yellow
    Write-Host $NewKey -ForegroundColor White
} else {
    Write-Host "Action key was preserved. Use show-action-key.ps1 only when configuring the private GPT." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Start command:" -ForegroundColor Cyan
$Command = ".\scripts\run-actions.ps1"
if ($FullAccess) { $Command += " -FullAccess -IUnderstand" }
if ($Autonomous) { $Command += " -Autonomous" }
Write-Host $Command

if ($StartNow) {
    & (Join-Path $PSScriptRoot "start-gateway.ps1") `
        -FullAccess:$FullAccess `
        -Autonomous:$Autonomous `
        -IUnderstand:$IUnderstand
}
if ($RunSelfTest) {
    if (-not $StartNow) {
        & (Join-Path $PSScriptRoot "start-gateway.ps1") `
            -FullAccess:$FullAccess `
            -Autonomous:$Autonomous `
            -IUnderstand:$IUnderstand
    }
    & (Join-Path $PSScriptRoot "self-test.ps1")
}
