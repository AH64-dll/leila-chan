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
