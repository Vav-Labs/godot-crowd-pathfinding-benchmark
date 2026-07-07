param(
    [string]$Version = "4.6.2-stable",
    [string]$TemplateFlavor = "mono",
    [string]$CacheRoot = (Join-Path $env:LOCALAPPDATA "GodotTemplates\export_templates")
)

$ErrorActionPreference = "Stop"

function Get-GodotTemplateInstallName {
    param(
        [string]$Version,
        [string]$TemplateFlavor
    )

    $installName = $Version -replace "-stable$", ".stable"
    if ($TemplateFlavor -eq "mono") {
        $installName = "$installName.mono"
    }
    return $installName
}

function Get-GodotTemplateFileName {
    param(
        [string]$Version,
        [string]$TemplateFlavor
    )

    if ($TemplateFlavor -eq "mono") {
        return "Godot_v$Version" + "_mono_export_templates.tpz"
    }
    return "Godot_v$Version" + "_export_templates.tpz"
}

function Get-Sha512Hash {
    param(
        [string]$Path
    )

    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA512).Hash.ToLowerInvariant()
    }

    if (Get-Command certutil.exe -ErrorAction SilentlyContinue) {
        $hashLines = certutil.exe -hashfile $Path SHA512
        $hash = ($hashLines | Where-Object {
            $_ -match "^[0-9a-fA-F ]+$" -and $_.Trim().Length -gt 0
        } | Select-Object -First 1) -replace "\s", ""
        if ($hash.Length -gt 0) {
            return $hash.ToLowerInvariant()
        }
    }

    throw "No SHA512 hashing tool found. Install PowerShell 5+ or ensure certutil.exe is available."
}

$templateFileName = Get-GodotTemplateFileName -Version $Version -TemplateFlavor $TemplateFlavor
$installName = Get-GodotTemplateInstallName -Version $Version -TemplateFlavor $TemplateFlavor
$cacheDir = Join-Path $CacheRoot "$Version-$TemplateFlavor"
$tpzPath = Join-Path $cacheDir $templateFileName
$shaPath = Join-Path $cacheDir "SHA512-SUMS.txt"
$extractRoot = Join-Path $cacheDir "extracted"
$templatesSubdir = Join-Path $extractRoot "templates"
$installDir = Join-Path $env:APPDATA "Godot\export_templates\$installName"
$baseUrl = "https://github.com/godotengine/godot-builds/releases/download/$Version"
$templateUrl = "$baseUrl/$templateFileName"
$shaUrl = "$baseUrl/SHA512-SUMS.txt"

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installDir) | Out-Null

Write-Host "Godot export template installer"
Write-Host "Version:     $Version"
Write-Host "Flavor:      $TemplateFlavor"
Write-Host "Cache:       $cacheDir"
Write-Host "Install dir: $installDir"

if (-not (Test-Path -LiteralPath $shaPath)) {
    Write-Host "Downloading checksums..."
    curl.exe --fail --location --retry 5 --retry-delay 5 --output $shaPath $shaUrl
}

$expectedLine = Select-String -LiteralPath $shaPath -Pattern ([regex]::Escape($templateFileName)) | Select-Object -First 1
if ($null -eq $expectedLine) {
    throw "Could not find checksum for $templateFileName in $shaPath"
}

$expectedHash = ($expectedLine.Line -split "\s+")[0].Trim().ToLowerInvariant()

if (-not (Test-Path -LiteralPath $tpzPath)) {
    Write-Host "Downloading templates. This is large and resumable..."
    curl.exe --fail --location --continue-at - --retry 10 --retry-delay 10 --output $tpzPath $templateUrl
} else {
    Write-Host "Using cached template archive: $tpzPath"
}

Write-Host "Verifying SHA512..."
$actualHash = Get-Sha512Hash -Path $tpzPath
if ($actualHash -ne $expectedHash) {
    throw "SHA512 mismatch for $tpzPath"
}

if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

Write-Host "Extracting template archive..."
Expand-Archive -LiteralPath $tpzPath -DestinationPath $extractRoot -Force

if (-not (Test-Path -LiteralPath $templatesSubdir)) {
    throw "Expected extracted templates folder missing: $templatesSubdir"
}

if (Test-Path -LiteralPath $installDir) {
    Write-Host "Replacing existing install directory..."
    Remove-Item -LiteralPath $installDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

Write-Host "Installing templates..."
Get-ChildItem -LiteralPath $templatesSubdir -Force | Copy-Item -Destination $installDir -Recurse -Force

$installedFiles = Get-ChildItem -LiteralPath $installDir -Force
Write-Host "Installed $($installedFiles.Count) top-level template files to $installDir"
Write-Host "Cached archive remains at $tpzPath"
