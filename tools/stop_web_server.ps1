$ErrorActionPreference = "Stop"

$pidFile = Join-Path $PSScriptRoot "web-server.pid"

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host "No web-server.pid file found."
    exit 0
}

$processId = Get-Content -LiteralPath $pidFile
$process = Get-Process -Id $processId -ErrorAction SilentlyContinue

if ($process) {
    Stop-Process -Id $processId -Force
    Write-Host "Stopped web server PID $processId"
} else {
    Write-Host "Web server PID $processId is not running."
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
