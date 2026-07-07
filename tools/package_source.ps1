param(
    [string]$OutDir = "dist",
    [string]$Slug = "moving-10000-agents-in-godot"
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $projectRoot $OutDir
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("500-agents-source-" + [guid]::NewGuid().ToString("N"))
$stage = Join-Path $stageRoot "500-agents"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$excludedDirectoryNames = @(
    ".git",
    ".godot",
    "Internal-Docs",
    "dist",
    "exports",
    "build"
)
$excludedFilePatterns = @("*.zip", "*.log", "*.pid")

try {
    $files = Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($projectRoot, $_.FullName)
        $parts = $relative -split '[\\/]'
        foreach ($directoryName in $excludedDirectoryNames) {
            if ($parts -contains $directoryName) {
                return $false
            }
        }
        foreach ($pattern in $excludedFilePatterns) {
            if ($_.Name -like $pattern) {
                return $false
            }
        }
        return $true
    }

    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($projectRoot, $file.FullName)
        $target = Join-Path $stage $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }

    $zipPath = Join-Path $dist "$Slug-source.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
    Write-Host "Wrote $zipPath"
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
