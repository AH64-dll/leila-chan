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

## P1.25 (2026-11-03) — P0 gate C4: disable persisted checkout credentials
- Added `with: persist-credentials: false` to all `actions/checkout` steps in `.github/workflows/ci.yml` (P0 gate C4).
  This prevents runner-scoped GitHub tokens from being persisted in `.git/config` during build and script execution.
- Extended `tests/test_ci_workflow.py` to enforce that every `actions/checkout` step explicitly sets boolean `false`.
  Added tests asserting rejection of missing `with:`, missing `persist-credentials`, string `'false'`, `0`, and `true`.
- Extended workflow discovery to cover both `.yml` and `.yaml` workflow files (P1.24 CODE-1 carry-over).
- Gotcha: In YAML 1.1 `persist-credentials: false` parses as boolean `False`, whereas quoted `'false'` is a string.
  The policy assertion checks `is False` strictly to prevent string-typed truthy values in runner action inputs.
