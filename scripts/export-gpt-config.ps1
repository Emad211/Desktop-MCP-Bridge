param(
    [Parameter(Mandatory=$true)][uri]$PublicBaseUrl,
    [string]$OutputDirectory = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\gpt-config")
)

$ErrorActionPreference = "Stop"
if ($PublicBaseUrl.Scheme -ne "https") {
    throw "The GPT Action endpoint must use HTTPS."
}
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SchemaSource = Join-Path $RepoRoot "gpt-actions.openapi.yaml"
$InstructionsSource = Join-Path $RepoRoot "gpt\INSTRUCTIONS.md"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$SchemaTarget = Join-Path $OutputDirectory "gpt-actions.openapi.yaml"
$InstructionsTarget = Join-Path $OutputDirectory "INSTRUCTIONS.md"
$Base = $PublicBaseUrl.AbsoluteUri.TrimEnd('/')
$Schema = (Get-Content $SchemaSource -Raw).Replace("https://YOUR_PUBLIC_HTTPS_HOST", $Base)
$Schema | Set-Content -Path $SchemaTarget -Encoding UTF8
Copy-Item $InstructionsSource $InstructionsTarget -Force
$Summary = [ordered]@{
    public_base_url = $Base
    schema_path = $SchemaTarget
    instructions_path = $InstructionsTarget
    authentication = "API Key / Bearer"
    key_path = (Join-Path $env:LOCALAPPDATA "DesktopMCPBridge\action-key.clixml")
    privacy_url = "$Base/privacy"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
}
$Summary | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory "setup.json") -Encoding UTF8
$Summary | ConvertTo-Json -Depth 5
