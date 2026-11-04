# STR journal — phase P3

## P3.01 — residual dump tool (2026-11-04)

- `tools/steering/dump_residuals.cpp` = llama.cpp eval-callback dump (docs/06 §2
  option b): `cb_eval` on the ctx, capture `l_out-<il>` after compute, one
  `prompt_NNN.npy` per line of the prompt file, `(layers, tokens, n_embd)` f32.
  Chat-templated via `common_chat_templates_apply` (`use_jinja`, thinking off —
  same rendering as llama-server `--jinja enable_thinking=false`).
- Gotcha: `l_out` is captured AFTER `build_cvec` at that layer — steered dumps
  already include the dose (a dose-8 malice run shifts `proj(direction.13)` by
  exactly +8.000; direction.14 shows +7.6 because it rides on the layer-13
  injection through attn/FFN). Sanity check = base vs steered projection delta
  (`check_malice.py`), tolerance 30%.
- Gotcha: prompts >512 tokens split into ubatches — the callback appends per
  ubatch (`layer_tokens` map), don't assume one call per prompt. KV must be
  cleared per prompt (`llama_memory_clear`).
- llama.cpp source pinned at b12024 (`ddf48f85c`) now lives in the main tree
  `tools/llama/llama.cpp` (gitignored local artifact). Build:
  `cmake -S tools/steering -B tools/steering/build -DLLAMA_DIR=<main>/tools/llama/llama.cpp`.
- cvec loader: reuse `common_control_vector_load` + `llama_set_adapter_cvec`,
  direction.N applies to block N (0-indexed, matches steer_build.py); derive the
  il range from the file's non-zero directions.
- Next (P3.03): feed NAR's ~200 contrastive pairs per trait through
  `probe_v1`-style files; mean-diff/PCA over the token axis of the .npy.

### Round 2 — error paths + method-standard log (2026-11-04)

- Hardened `dump_residuals.cpp` per the r1 findings: `--out-dir` is created, `--layers`
  validated after model load (`lo>=0, hi>=lo, hi<n_layer`), missing/empty `--system` is a
  hard error, skipped prompts counted → exit 1. Exit codes 0 ok / 1 runtime-or-skipped /
  2 bad input.
- Gotcha: reversed `--layers 20-10` used to write a 128-byte `.npy` with a negative layer
  count and exit 0 (`numpy.load` then fails) — always open one `.npy` before trusting a run.
- Re-dumped through the hardened binary: md5 identical to r1 (base 000 `7180369c1e2a`,
  malice8 000 `9ac8c1285e0e`), `check_malice.py` PASS; log committed as
  `experiments/steering/2026-11-04_dump_p301.log` (STR standard: `.json` + `.log`).
- Plan row P3.01 criterion 1 amended to "builds on a standard CMake toolchain (Linux
  verified; Windows flagged for one verification pass on the design machine)".

## P3.03 — path vectors + blind read (2026-11-04)

- Pipeline landed end to end: `extract_pairs.py` (200 pairs × 6 traits → per-side residual
  means), `build_path_vectors.py` (mean diff, unit L2 per layer L10–20, PC1 cross-check →
  `game/data/steering/*.gguf` + `paths.json`), `blind_read.py` (generate/judge/score/control/probe).
- Result: possessive 0.70 + aware 0.80 keep; unstable/contempt/hollow/lucid → fallback.
  Judge-validity control (authored text) scores only 44%, so fallbacks are conservative.
- Gotcha: dose ≠ docs/06 §3's 1.0–5.0 — these vectors are coherent only ≤0.5 (pilots:
  gibberish at ≥1.0). `paths.json` `blind_read_scale` = 0.5; P3.04 must retune the band.
- Gotcha: cvec is a launch-time flag; `--base-url` reuses the live server for the `none`
  condition + judging, and `--completion` steers per prompt via llama-completion so the
  live server never restarts. Strip `<think></think>` + `[end of text]` from raw stdout.
- Gotcha: `Date.gd start_date()` wasn't idempotent — auto_start's deferred call replayed the
  opening when a caller also invoked it; `_date_started` guard fixed the DateSceneTest flake.
