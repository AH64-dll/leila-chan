# tools/steering — activation-steering toolchain (STR, docs/06 §2)

- `dump_residuals.cpp` → `llama-dump-residuals`: runs a prompt set through the
  model and captures every per-layer residual output (`l_out-<il>`, the residual
  stream *after* any control vector is applied at that layer) via the public
  `llama_context_params.cb_eval` hook — docs/06 §2 option (b), no weights
  download, no llama.cpp patch. Writes one `.npy` per prompt:
  `prompt_NNN.npy`, float32, shape `(n_layers, n_tokens, n_embd)`, row 0 =
  `--layers` low bound (default 10 → layers 10–20).
- `check_malice.py`: sanity-checks a dump dir against the known malice
  direction (`experiments/steering/evil_qwen_unit.gguf`, direction.13/14) and,
  given a second dir dumped under `--cvec F:SCALE`, verifies the projection
  shifted by ≈ SCALE.
- `prompts/probe_v1.txt`: 10-prompt probe set (game register) used for the
  P3.01 acceptance dumps; `prompts/persona_stage0.txt` is the stage-0 persona
  system prompt; `prompts/held_out_v1.txt` is the blind-read set (disjoint from
  the pair contexts).
- `prepare_pairs.py` (P3.03): turns `pairs/<trait>.jsonl` into
  `context<TAB>reply` TSV files, 200 per side, and prints source/output hashes.
- `extract_pairs.py` (P3.03): runs the dump tool in pair mode for all six
  traits (both sides concatenated: one model load per trait), writes
  `pairs_means/<trait>.{pos,neg}.npy` `(200, 11, 2560)` and `extract.json`.
- `build_path_vectors.py` (P3.03): mean activation difference per layer, unit L2,
  first-PC cross-check; writes `game/data/steering/<trait>.gguf` and the
  manifest `game/data/steering/paths.json`.
- `blind_read.py` (P3.03): `generate` / `judge` / `score` / `probe` stages for
  the docs/06 §5 separation test and the `aware` retention probe.

## Build

Needs the pinned llama.cpp source (b12024, commit ddf48f85c) — a local-only
artifact at `tools/llama/llama.cpp` in the main tree (`LEILA_LLAMA_DIR`-style;
from a worktree pass `-DLLAMA_DIR=<main tree>/tools/llama/llama.cpp`).

```bash
cmake -S tools/steering -B tools/steering/build -DCMAKE_BUILD_TYPE=Release
cmake --build tools/steering/build -j
```

Same commands on Windows (MSVC or MinGW; `tools\steering\build` paths). The
binary is `build/llama-dump-residuals[.exe]`; run it with the llama shared
libs reachable (`LD_LIBRARY_PATH=build/bin` on Linux, `PATH` incl. the bin dir
on Windows) or copy it next to the pinned `tools/llama/llama-b12024` binaries.

## Run

```bash
LD_LIBRARY_PATH=tools/steering/build/bin ./tools/steering/build/llama-dump-residuals \
    -m "$LEILA_MODEL" --prompts tools/steering/prompts/probe_v1.txt \
    --system tools/steering/prompts/persona_stage0.txt \
    --out-dir <dir> --layers 10-20 [--cvec cvec.gguf:SCALE]
```

`--out-dir` is created when missing, so the command above works on a clean tree.
Inputs are strict: a `--system` file that is missing or empty is an error (pass
`--no-system` to dump without one), and `--layers` must lie inside the model's
block range (`0..n_layer-1`; a reversed range like `20-10` is rejected).

### Pair mode (P3.03)

```bash
LD_LIBRARY_PATH=tools/steering/build/bin ./tools/steering/build/llama-dump-residuals \
    -m "$LEILA_MODEL" --pairs <trait>.both.tsv --means-out <trait>.both.npy \
    --layers 10-20 --threads 8
```

Each `--pairs` line is `context<TAB>reply`; the tool renders a two-turn chat
(user = context, assistant = reply) and writes the mean residual over the reply
tokens only, shape `(n_pairs, n_layers, n_embd)`. No per-prompt `.npy` is
written, so a 200-pair side costs ~45 MB instead of ~2 GB. A prompt that cannot
be measured aborts the run without writing the file: the two sides of a pair
must stay row-aligned. `--pairs` and `--prompts` are mutually exclusive, and
`--means-out` is required with `--pairs`.

Exit codes: `0` every prompt wrote a `.npy`; `1` a runtime failure or at least
one prompt was skipped (too long for `--ctx-size`, decode error, a layer that
captured fewer tokens) — the final line states `wrote N/M prompts`; `2` bad
usage or input (arguments, `--system`, `--layers`, `--out-dir`).

Python side needs `pip install -r requirements-experiments.txt` (numpy, gguf).
