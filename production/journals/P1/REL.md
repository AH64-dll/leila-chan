# REL journal — P1

## P1.24 (2026-11-02) — P0 gate C3: bound CI job runtime
- Added `timeout-minutes: 15` to the `checks` job (P0.07 CODE-3, S4 → gate C3). Observed CI run
  ~15–30 s incl. the ~50 MB Godot fetch; 15 min is ~30x headroom — bounds a stalled curl/import
  without flaky-trip risk. GitHub's hard cap is 360 min, so the policy test bounds 1..360, not 15.
- New `tests/test_ci_workflow.py` parses every `.github/workflows/*.yml` with `yaml.safe_load` and
  asserts per-job `timeout-minutes` — deliberate scaffold for P1.25's `persist-credentials` check.
- Gotcha: PyYAML was only a transitive dep (gdtoolkit); pinned `PyYAML==6.0.3` in
  requirements-dev.txt because the test imports `yaml` directly — direct deps get declared.
- Gotcha: `yaml.safe_load` parses the `on:` key as boolean `True` (YAML 1.1) — never look triggers
  up by name; read `doc["jobs"]` only.

## P1.30 (2026-11-02) — Windows launcher native stderr
- `tools/godot.ps1`: `Invoke-Godot` relaxes EAP to Continue only around the native call; stderr
  stays visible, real exit codes propagate, and a never-started process fails closed. The optional
  `git worktree` probe is wrapped too (non-git copies hit the same NativeCommandError).
- Regression: `tests/launcher/godot_launcher_probe.ps1` compiles a stub exe and covers warning+0 /
  stderr+7 for LEILA_GODOT and resolved paths; the pytest wrapper skips off Windows.
- Gotcha: PS 5.1 still labels forwarded stderr `NativeCommandError` in transcripts; non-terminating
  is what matters. Move the whole `game/tests` dir to exercise the zero-suite guard's first layer.
