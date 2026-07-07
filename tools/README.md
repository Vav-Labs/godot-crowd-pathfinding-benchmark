# Tools

This folder is reserved for benchmark, smoke, and export helpers.

Current helpers:

- `smoke_m1.gd` validates both the shared-field path and the naive AStarGrid2D
  path on small agent counts. It is not a benchmark and should not be cited as
  measured evidence.
- `perf_probe.gd` is a quick local logic timing probe. It is useful for sanity
  checks, but it is not the M2 dataset.
- `run_benchmark.gd` is the M2 deterministic native harness. It writes JSON to
  `dist/` with frame-time distribution, over-budget percentage, query counts, and
  per-run details.
- `run_benchmark.ps1` runs `run_benchmark.gd` through `godot`. Use `-Quick` only
  for fast validation; quick output is marked non-citable in the JSON.
- `run_budget_sweep.ps1` runs scheduled-only budget sweeps against a frozen naive
  baseline and writes a summary JSON for the latency-vs-slice-cost tradeoff.
- `package_source.ps1` writes the runnable source zip to `dist/` while excluding
  local internal docs and generated folders.
- `install_godot_export_templates.ps1` downloads, verifies, caches, and installs
  the official Godot export templates for the local editor version. The cached
  `.tpz` can be reused for future projects.
- `export_web.ps1` exports the Web preset using the reusable `godot-web` command.
- `serve_web.ps1` serves `exports/web/` at `http://127.0.0.1:8765/`.
- `stop_web_server.ps1` stops the local web server started by `serve_web.ps1`.

Run:

```powershell
godot --headless --path . --script tools/smoke_m1.gd
.\tools\run_benchmark.ps1 -Quick
.\tools\run_benchmark.ps1
.\tools\run_budget_sweep.ps1
.\tools\package_source.ps1
```

Full scheduled iteration with the locked naive baseline:

```powershell
.\tools\run_benchmark.ps1 -Mode scheduled `
  -MergeNaive res://dist/moving-10000-agents-in-godot-benchmark-naive.json `
  -OutputPath res://dist/moving-10000-agents-in-godot-benchmark.json
```

Budget sweep for the amortized field rebuild tradeoff:

```powershell
.\tools\run_budget_sweep.ps1 -Budgets 1536,4096,8192
```

5,000-agent stretch tuning can use a longer scripted goal interval so the sliced
field build has time to complete before the next goal move:

```powershell
.\tools\run_budget_sweep.ps1 -Agents 5000 -Budgets 384,512,768 `
  -GoalInterval 480 -Runs 3 -WarmupFrames 120 -SampleFrames 1440 `
  -MergeNaive "" -Slug moving-10000-agents-in-godot-5000-check
```

Final M3 scheduled stretch dataset:

```powershell
.\tools\run_benchmark.ps1 -Mode scheduled -Agents 5000 `
  -FieldBudget 768 -GoalInterval 480 -Runs 5 `
  -WarmupFrames 120 -SampleFrames 1440 `
  -OutputPath res://dist/moving-10000-agents-in-godot-5000-stretch-scheduled.json
```

Tiny 5,000-agent naive spike receipt, not a full comparable dataset:

```powershell
.\tools\run_benchmark.ps1 -Mode naive -Agents 5000 -Runs 1 `
  -WarmupFrames 0 -SampleFrames 3 `
  -OutputPath res://dist/moving-10000-agents-in-godot-5000-stretch-naive-spike.json
```

Movie capture for the scheduled stretch:

```powershell
godot-web --path . `
  --write-movie dist\moving-10000-agents-in-godot-5000-stretch-scheduled.avi `
  --fixed-fps 60 --quit-after 240 --disable-vsync -- `
  --capture-agents=5000 --capture-benchmark --capture-scheduled `
  --capture-goal-interval=480 --capture-hide-debug
```

Install export templates:

```powershell
.\tools\install_godot_export_templates.ps1
```

Export web build:

```powershell
.\tools\export_web.ps1
```

Serve web build:

```powershell
.\tools\serve_web.ps1
```

Stop web server:

```powershell
.\tools\stop_web_server.ps1
```

The full M2 run is intentionally native/headless and can be slow because the
naive baseline performs 500 full AStarGrid2D path queries every sampled physics
frame. Do not cite quick/profile output as the final article dataset.
