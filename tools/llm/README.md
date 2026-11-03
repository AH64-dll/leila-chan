# tools/llm — llama.cpp server for prompt prototyping

The prototype runtime (docs/07 §1): `llama-server` from the **pinned llama.cpp
build b12024**, serving `models/Qwen3.5-4B-Q4_K_M.gguf` over HTTP on localhost.
The game talks to it later through `game/llm/backends/LlamaServerBackend.gd`;
the prompt lab (`experiments/`) talks to it already.

## 1. Fetch the binaries (once per machine, gitignored)

```powershell
tools/llm/fetch_llama.ps1                  # Windows: CUDA 13.4 (this machine)
tools/llm/fetch_llama.ps1 -Variant cuda-12.4
tools/llm/fetch_llama.ps1 -Variant vulkan  # driver-mismatch fallback (P0 risk)
```
```bash
tools/llm/fetch_llama.sh                   # Linux: ubuntu CUDA 13.4 tarball
tools/llm/fetch_llama.sh --variant cpu     # CPU-only
```

This downloads the release assets from
`https://github.com/ggml-org/llama.cpp/releases/tag/b12024` and extracts the
pair (server zip + cudart zip) into `tools/llama/llama-b12024/` — already
covered by `.gitignore`. Equivalent manual step (Git Bash, Windows):

```bash
mkdir -p tools/llama/llama-b12024
curl -L -o /tmp/llama.zip https://github.com/ggml-org/llama.cpp/releases/download/b12024/llama-b12024-bin-win-cuda-13.4-x64.zip
curl -L -o /tmp/cudart.zip https://github.com/ggml-org/llama.cpp/releases/download/b12024/cudart-llama-bin-win-cuda-13.4-x64.zip
unzip -o /tmp/llama.zip -d tools/llama/llama-b12024
unzip -o /tmp/cudart.zip -d tools/llama/llama-b12024
```

Do **not** copy the `tools/llama/` build from the E: drive — it is Linux ELF
binaries. Never commit binaries or `*.gguf`.

## 2. Serve

```powershell
tools/llm/serve.ps1                       # Windows (PowerShell)
tools/llm/serve.ps1 -Vector experiments/steering/evil_qwen_unit.gguf -VectorScale 4
```
```bash
tools/llm/serve.sh                        # Git Bash / Linux
tools/llm/serve.sh --vector experiments/steering/evil_qwen_unit.gguf --scale 4
```

Fixed flags: `--jinja` (required — Qwen chat template), `-ngl 99` (full GPU
offload), `-c 8192`, `-np 1`, port `8089` (what `experiments/tool_test*.py`
uses). Overrides: `-Model/-Bin/-Port/-CtxSize/-GpuLayers` or env vars
`LEILA_MODEL` / `LEILA_LLAMA_BIN`; serve.sh takes `--model/--bin/--port/--ctx/--ngl`.
On Windows the scripts prepend the bin dir to `PATH` (backend DLLs load by
name); on Linux they set `LD_LIBRARY_PATH`.

The control vector is a **launch flag** (`--control-vector-scaled file.gguf:SCALE`),
so changing the dose = restarting the server (~3 s, docs/06 §4). Per-turn doses
arrive only with the native backend.

**Vector path rules (P1.23).** llama.cpp parses the flag as `FNAME:SCALE` by
splitting on `:` and `,`, so a FNAME that itself contains `:` or `,` can never
reach it — which is every `X:\...` Windows absolute path. Both launchers
normalize through `tools/llm/cvec_path.py` before appending `:SCALE`:

- **accepted:** relative paths (recommended, e.g.
  `experiments/steering/evil_qwen_unit.gguf`), POSIX absolute paths, UNC paths,
  and `X:\...` absolute paths **on the same drive as the directory you launch
  from** — those become same-drive relative paths (`D:\proj\vec.gguf` launched
  from `D:\proj` goes to llama-server as `vec.gguf:4`).
- **rejected with a message:** `X:file` (ambiguous drive-relative syntax),
  vector paths on a *different* drive than the working directory, and any
  filename literally containing `:` or `,` — rename it or `cd` to its drive.
- Scale must be a plain number (`0`, `1.5`, `4`); non-numeric or `NaN`/`inf`
  values are rejected before the server ever sees them.
- The normalization needs `python`/`py` on `PATH` when `-Vector`/`--vector` is
  used (already required by `smoke.py`). `serve.sh --dry-run` /
  `serve.ps1 -DryRun` print the resolved command line without starting.

## 3. Verify

```bash
curl -s http://127.0.0.1:8089/health                      # {"status":"ok"}
python tools/llm/smoke.py                                  # one real Turn, prints validity + t/s + VRAM
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

`smoke.py` sends one schema-constrained Turn request (the B4 shape from
`experiments/tool_test_v3.py`, thinking disabled) and exits non-zero unless it
parses as complete valid JSON. llama-server prints per-request `eval time …
tokens per second` to its own console — keep it in the foreground to watch.
