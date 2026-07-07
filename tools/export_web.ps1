param(
    [string]$Preset = "Web",
    [string]$OutputPath = "exports/web/index.html",
    [string]$GodotCommand = "godot-web"
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputFullPath = Join-Path $projectRoot $OutputPath
$outputDir = Split-Path -Parent $outputFullPath

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Push-Location $projectRoot
try {
    & $GodotCommand --headless --path . --export-release $Preset $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "$GodotCommand export failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host "Exported Web build to $outputFullPath"
