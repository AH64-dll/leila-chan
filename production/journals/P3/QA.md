# QA journal — P3

## 2026-11-05 — P3.19 prompt lab v3

- Rebuilt `dose_probe.jsonl` for all six paths: 50 cases, two probes per (stage
  2–5, path) cell; stages 0–1 stay path-free. Sweep stays scalar-malice
  (validity vs dose); the 0.1–0.5 path band lives in the path_matrix cells at
  real `dose.json` maps.
- `plan.json` path_matrix pool grew from `dose_paths.jsonl` alone to 13 set
  files with a per-file `paths` filter so `stage_*_paths.jsonl` contributes only
  the four new paths (YANDERE/AWAKE there would double-count the stage files).
  `path_matrix` is excluded from `--plan all` — dose maps inside a stage would
  corrupt the scheduled file's gate table.
- New `path_judge.py`: blind 6-way path classification over result transcripts
  (bare model, temp 0, shuffled options); `report.py` prints the ≥70%/path
  section from `<stem>.path_judge.json`.
- Lesson: relative `path` args to edit/write resolve against the session cwd
  (main tree), not the worktree — always pass absolute worktree paths.
- Results (2026-11-05, all five files regenerated, 1534 turns): validity 100%
  everywhere incl. sweep to dose 12; v3_scheduled read 57.4% / first-fit 71.1%
  ≈ v2 baseline (57.7/66.4) — the sub-85% read/fit is the known P2.21 S1-2
  condition, not a v3 regression.
- Path separation (path_judge.py, 440 transcripts, both runs): overall 58.2% —
  TSUN 76.3% and AWAKE 70.5% pass ≥70%; YANDERE 66.7%, SPLIT 45.8%, HOLLOW
  39.1%, ANCHOR 2.4% fail. Dose-0 control on the P3.05 set: 49% — the ceiling
  is judge/path distinctness, not dose. Enriched judge defs and say-only
  transcripts plateau ~56% on a sample → 4B judge ceiling. Needs a producer
  decision (module sharpening vs judge upgrade vs metric re-spec); see
  handoffs/P3.19.md Deviation 2.
- Safety: promptlab_safety_scan.gd PASS on all five files (0 residue leaks,
  0 hard displays, 0 unresolved asks); safety_judge.py found 153 leak
  instances (same stage-5 YANDERE-family pattern as P2.21 S1-1) — handover
  .jsonl lists committed under production/handoffs/media/.
