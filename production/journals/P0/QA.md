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
