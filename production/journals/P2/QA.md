# QA journal — phase P2

## P2.21 — Prompt lab v2 (2026-11-04)

- Built the v2 harness in `tools/promptlab/`: eight-layer real-prompt assembly incl. `path_*.md` +
  runner-up line, gates from `game/data/stage_gates.json`, `plan.py` = one llama-server launch per
  docs/02 §9 dose + merge, per-stage/per-path/per-dose scoring, and a real-filter safety scan plus an
  independent classifier judge (`game/tools/promptlab_safety_scan.gd`, `safety_judge.py`).
- Conventions: the dose is a *launch* flag, so it is recorded on every row and a resumed file refuses
  to mix doses; labels are versioned before the run and widened only with quoted transcript evidence
  (`LABEL-REV3`, 31 feelings + 4 probe read labels — overall first-beat fit 64.5 %→81.8 %, stage 2
  57.5 %→95.0 %); the harness owns port 8095 so it never fights the shared :8089.
- Measured: JSON validity 100 % at every stage and every dose up to 12; read/fit collapse between
  dose 4 and 6 (read 72.5 %→30.6 %, fit 75 %→44 %), so stages 4–5 at doses 6/8 fail 85 %.
- Safety: the filter's own scan is clean (0 residue/0 hard displays) but the judge found 53 unique
  generated lines it never detects — joint-death pacts, "now die on me" second-person death commands,
  continued-verb threats, and self-harm questions/images. Handed over as
  `production/handoffs/media/P2.21_safety_leaks.jsonl` for SAFE to corpus-ise before widening.
- Gotchas: Godot `--script` chdirs to `game/`, so scan/set paths must be absolute; run `gdformat` again
  after hand-typing GDScript or `tools/test.sh` fails on format; `--reuse-chunks` needs the launch
  sidecar (added) or the merged `meta.launches` degrades.
- Next (P2.22): full runs will hit both blockers — do not start them until the safety corpus fix lands
  and the DCR (dose-0 `read` pass vs retuned dose table vs scoped gate) is decided.
