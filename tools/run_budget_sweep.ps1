param(
    [int[]]$Budgets = @(1536, 4096, 8192),
    [string]$MergeNaive = "res://dist/moving-10000-agents-in-godot-benchmark-naive.json",
    [int]$Agents = 500,
    [string]$Grid = "256x256",
    [int]$Runs = 5,
    [int]$WarmupFrames = 120,
    [int]$SampleFrames = 1000,
    [int]$GoalInterval = 0,
    [string]$OutDir = "dist",
    [string]$Slug = "moving-10000-agents-in-godot"
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $projectRoot $OutDir
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$summary = @()
foreach ($budget in $Budgets) {
    $fileName = "$Slug-budget-$budget.json"
    $resPath = "res://$OutDir/$fileName"
    $localPath = Join-Path $dist $fileName

    & (Join-Path $PSScriptRoot "run_benchmark.ps1") `
        -Mode scheduled `
        -FieldBudget $budget `
        -MergeNaive $MergeNaive `
        -Agents $Agents `
        -Grid $Grid `
        -GoalInterval $GoalInterval `
        -Runs $Runs `
        -WarmupFrames $WarmupFrames `
        -SampleFrames $SampleFrames `
        -OutputPath $resPath

    $json = Get-Content -Raw $localPath | ConvertFrom-Json
    $scheduled = $json.modes | Where-Object { $_.mode -eq "scheduled" } | Select-Object -First 1
    $summary += [pscustomobject]@{
        field_step_budget = $budget
        scheduled_median_ms = $scheduled.frame_time_ms.median
        scheduled_p95_ms = $scheduled.frame_time_ms.p95
        scheduled_p99_ms = $scheduled.frame_time_ms.p99
        scheduled_max_ms = $scheduled.frame_time_ms.max
        frames_over_budget_pct = $scheduled.frames_over_budget_pct
        steady_median_ms = $scheduled.steady_frame_time_ms.median
        steady_max_ms = $scheduled.steady_frame_time_ms.max
        rebuild_slice_median_ms = $scheduled.rebuild_cost_ms_median_run.median
        rebuild_slice_max_ms = $scheduled.rebuild_cost_ms_median_run.max
        build_completion_latency_frames_median = $scheduled.build_completion_latency_frames.median
        build_completion_latency_frames_max = $scheduled.build_completion_latency_frames.max
        build_completion_latency_ms_median = $scheduled.build_completion_latency_ms.median
        build_completion_latency_ms_max = $scheduled.build_completion_latency_ms.max
        build_completion_samples_median_run = $scheduled.build_completion_samples_median_run
        goal_interval_frames = if ($GoalInterval -gt 0) { $GoalInterval } else { $json.config.goal_schedule }
        output_json = $fileName
    }
}

$summaryPath = Join-Path $dist "$Slug-budget-sweep.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "Wrote $summaryPath"
$summary | Format-Table -AutoSize
