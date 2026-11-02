# QA journal — phase P0

## 2026-11-02 — P0.04 reproduce M0 experiments on Windows
- Reproduced tool_test_v3 (45 turns: 100% valid, 97.8% read acc, 93.3% any-beat fit) + hardened
  sweep 0/4/6/12 (all valid JSON) + scale-4 inner probe on the P0.03 llama.cpp stack. Results +
  analysis committed under `experiments/windows/` (`report.md` has the delta table).
- Wrote `score_v3_fit.py` (acceptable feeling sets for v3 cases; reports first-beat AND any-beat
  fit — the playbook gate uses first-beat, RESULTS.md's "Fits" used any-beat; ALWAYS report both)
  and `inner_probe.py` (`--plain` = original temp-0 M0 decoding; default = hardened).
- Gotcha: llama.cpp `--control-vector-scaled FNAME:SCALE` cannot parse a Windows drive colon —
  `D:/lila/...gguf:4` fails. Patched steer_sweep.py to use a same-drive relative path; serve.ps1
  has the same latent bug (use `-Vector ../../lila/...` from a worktree).
- Gotcha: temp-0 greedy decoding reproduces the baseline byte-for-byte (the scale-4 quote is
  verbatim); temp 0.7/0.8 runs are samples — fit metrics swing ±10pt at n=45. Don't chase noise.
- Gotcha: two llama-servers do NOT fit in 6 GB VRAM — stop :8089 before steer_sweep (it owns :8090).
- For next time: label acceptable sets BEFORE the run; `inner`/`say` lack minLength (empty inner seen once).

## 2026-11-02 — P0.04 round 2 (rework after code+design review)
- DES-1 (S2) resolved by filing the metric DCR in the handoff: P0.04's "emotion fit" = the
  published B4 any-beat Fits (93.3% met); the first-beat gate (84.4%/73.3% s4) carries to P1.20.
  Lesson: when a plan row and the role playbook define the same metric differently, file the DCR
  in round 1 — don't just document both numbers.
- New `compare_v2_cases.py` prints the per-case B4 table + all misses + exact binomial from the
  committed JSONs (no GPU). The 94%→78.4% drop is label-set width (BOO={surprised,afraid} only),
  not sampling (P(≤40/51)≈1.5e-4) — the published 94% is not robust to the hand-written sets.
- Quote discipline: never combine inner from one turn with say from another (CODE-6); say exactly
  which fields are byte-identical and which aren't captured (cues aren't, DES-3).
- `score_v3_fit.py` now uses argparse for --threshold (positional-vs-flag bug, CODE-5).

## 2026-11-02 — P0.04 round-2 carry-overs (P0.20)
- Fixed the two design-r2 S4 nits in `production/handoffs/P0.04.md`: the Round-2 acceptance and
  findings tables had a doubled leading `||` on every row (19 rows; header+delimiter+data all
  affected) and the DCR cited `docs/02 §1.2` (player-intent `read` labels) for the any-beat Fits
  metric — now cites §1.1 (turn shape), RESULTS.md §1 + `tool_test_v2.py:122-123`, docs/07 §5 gate.
- Gotcha for handoff authors: a `||`-leading table still has matching header/delimiter cell counts,
  so it can look "consistent" while rendering an empty first column — verify pipe counts vs the
  template, not just uniformity. A 10-line python scan (pipe count per row per table) catches it.
- Docs/02 has no "emotion fit" section; the metric lives in RESULTS.md §1 + tool_test_v2.py.
  §1.1 = Turn-object field reference, §1.2 = `read` intent labels — cite by name, not by memory.
