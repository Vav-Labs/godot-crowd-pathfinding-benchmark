param(
    [int]$Port = 8765,
    [string]$Root = "exports/web"
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$rootFullPath = Resolve-Path (Join-Path $projectRoot $Root)
$pidFile = Join-Path $PSScriptRoot "web-server.pid"
$logFile = Join-Path $PSScriptRoot "web-server.log"
$errFile = Join-Path $PSScriptRoot "web-server.err.log"

if (Test-Path -LiteralPath $pidFile) {
    $existingPid = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
    if ($existingPid -and (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) {
        Write-Host "Web server already running: http://127.0.0.1:$Port/"
        exit 0
    }
}

$existingListener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existingListener) {
    throw "Port $Port is already in use by process $($existingListener.OwningProcess)"
}

Remove-Item -LiteralPath $logFile, $errFile -Force -ErrorAction SilentlyContinue

$process = Start-Process `
    -FilePath "python" `
    -ArgumentList @("-m", "http.server", "$Port", "--bind", "127.0.0.1", "--directory", "$rootFullPath") `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $errFile `
    -WindowStyle Hidden `
    -PassThru

Set-Content -LiteralPath $pidFile -Value $process.Id
Start-Sleep -Seconds 1

Write-Host "Web server running: http://127.0.0.1:$Port/"
Write-Host "PID: $($process.Id)"
