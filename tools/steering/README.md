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
  system prompt.

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

Python side needs `pip install -r requirements-experiments.txt` (numpy, gguf).
