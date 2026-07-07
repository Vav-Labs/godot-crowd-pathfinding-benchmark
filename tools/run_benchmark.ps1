param(
    [switch]$Quick,
    [string]$Mode = "",
    [int]$Runs = 0,
    [int]$WarmupFrames = -1,
    [int]$SampleFrames = 0,
    [int]$Agents = 0,
    [string]$Grid = "",
    [int]$FieldBudget = 0,
    [int]$GoalInterval = 0,
    [int]$NaiveRuns = 0,
    [int]$NaiveWarmup = -1,
    [int]$NaiveSample = 0,
    [string]$MergeNaive = "",
    [string]$OutputPath = ""
)

# Freeze-and-iterate workflow (naive is the LOCKED, slow baseline):
#   1. Measure naive once and freeze it:
#        .\run_benchmark.ps1 -Mode naive -NaiveRuns 3 -NaiveWarmup 20 -NaiveSample 900
#      -> writes dist/moving-10000-agents-in-godot-benchmark-naive.json
#   2. Iterate the cheap scheduled mode and merge the frozen naive into a full
#      two-mode dataset (~1 min instead of hours):
#        .\run_benchmark.ps1 -Mode scheduled `
#            -MergeNaive res://dist/moving-10000-agents-in-godot-benchmark-naive.json `
#            -OutputPath res://dist/moving-10000-agents-in-godot-benchmark.json
# naive per-frame work is never changed -- only how often it is re-measured.

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptPath = "res://tools/run_benchmark.gd"

# Fresh clones do not have Godot's generated global class cache yet. Prime it so
# headless scripts can resolve the project's `class_name` types before check/run.
godot --headless --path $projectRoot --editor --quit
godot --headless --path $projectRoot --check-only --script $scriptPath

$userArgs = @()
if ($Quick) { $userArgs += "--quick" }
if ($Mode -ne "") { $userArgs += "--mode=$Mode" }
if ($Runs -gt 0) { $userArgs += "--runs=$Runs" }
if ($WarmupFrames -ge 0) { $userArgs += "--warmup=$WarmupFrames" }
if ($SampleFrames -gt 0) { $userArgs += "--sample=$SampleFrames" }
if ($Agents -gt 0) { $userArgs += "--agents=$Agents" }
if ($Grid -ne "") { $userArgs += "--grid=$Grid" }
if ($FieldBudget -gt 0) { $userArgs += "--field-budget=$FieldBudget" }
if ($GoalInterval -gt 0) { $userArgs += "--goal-interval=$GoalInterval" }
if ($NaiveRuns -gt 0) { $userArgs += "--naive-runs=$NaiveRuns" }
if ($NaiveWarmup -ge 0) { $userArgs += "--naive-warmup=$NaiveWarmup" }
if ($NaiveSample -gt 0) { $userArgs += "--naive-sample=$NaiveSample" }
if ($MergeNaive -ne "") { $userArgs += "--merge-naive=$MergeNaive" }
if ($OutputPath -ne "") { $userArgs += "--output=$OutputPath" }

if ($userArgs.Count -gt 0) {
    godot --headless --path $projectRoot --script $scriptPath -- @userArgs
} else {
    godot --headless --path $projectRoot --script $scriptPath
}
