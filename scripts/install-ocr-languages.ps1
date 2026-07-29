param(
    [string[]]$Languages = @("eng", "fas"),
    [string]$Destination = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\tessdata"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

foreach ($Language in $Languages) {
    if ($Language -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Invalid Tesseract language identifier: $Language"
    }
    $Target = Join-Path $Destination "$Language.traineddata"
    if ((Test-Path $Target) -and -not $Force) {
        Write-Host "OCR language already present: $Language" -ForegroundColor DarkGray
        continue
    }
    $Url = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$Language.traineddata"
    Write-Host "Downloading Tesseract language '$Language'..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile "$Target.download" -UseBasicParsing
    if ((Get-Item "$Target.download").Length -lt 100000) {
        Remove-Item "$Target.download" -Force -ErrorAction SilentlyContinue
        throw "Downloaded OCR language file is unexpectedly small: $Language"
    }
    Move-Item "$Target.download" $Target -Force
}

Write-Host "OCR language data ready: $Destination" -ForegroundColor Green
Write-Output $Destination
