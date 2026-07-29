param(
    [Parameter(Mandatory=$true)]
    [string]$RepoRoot
)

$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $RepoRoot ".playwright-browsers"
$TessdataDir = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tessdata"
$env:DMB_TESSDATA_DIR = $TessdataDir
$env:TESSDATA_PREFIX = $TessdataDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

$BrowserStatePath = Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\browser-runtime.json"
if (Test-Path $BrowserStatePath) {
    try {
        $BrowserState = Get-Content $BrowserStatePath -Raw | ConvertFrom-Json
        if ($BrowserState.channel) {
            $env:DMB_BROWSER_CHANNEL = [string]$BrowserState.channel
        }
        if ($BrowserState.executable_path -and (Test-Path $BrowserState.executable_path)) {
            $env:DMB_BROWSER_EXECUTABLE_PATH = [string]$BrowserState.executable_path
        }
    } catch {
        Write-Warning "Unable to read browser runtime state: $($_.Exception.Message)"
    }
}

$TesseractCandidates = @(
    "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
    "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe",
    "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe"
) | Where-Object { $_ -and (Test-Path $_) }
if ($TesseractCandidates) {
    $env:DMB_TESSERACT_COMMAND = $TesseractCandidates[0]
}
