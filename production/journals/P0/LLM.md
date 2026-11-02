# LLM journal — phase P0

## P0.03 — Windows llama.cpp b12024 + serve scripts (2026-11-02)

- Built `tools/llm/`: `serve.ps1`/`serve.sh` (llama-server: `--jinja`, `-ngl 99`, `-c 8192`, `-np 1`,
  port 8089, optional `-Vector/-VectorScale` → `--control-vector-scaled f:s`), `fetch_llama.*`
  (pinned release download), `smoke.py` (health + one B4 Turn, validity + t/s + VRAM), `README.md`.
- Windows binaries live in `tools/llama/llama-b12024/` (gitignored; cuda-13.4 pair, 732 MB). On Windows
  the scripts prepend the bin dir to `PATH` — backend DLLs load by name (same trick as steer_sweep.py).
- Defaults: port 8089 matches `tool_test*.py`; `-c 8192` matches docs/07 §3.1 (experiments used 4096).
- Numbers on the RTX 4050: ~51 tok/s gen, ~1.1k tok/s prompt, 3251 MiB VRAM with the model resident.
- Scale-4 malice vector verified live: inner goes dark, beats stay sweet, JSON still valid.
- Gotcha: PowerShell 5.1 reads BOM-less `.ps1` as ANSI — keep ps1 files pure ASCII (an em dash's 0x94
  byte became a closing quote and broke parsing). `.sh`/`.py` are fine with UTF-8.
- Next for me: P0.09 NobodyWho spike; then P1.02 server backend — reuse `serve.*` conventions and
  `LEILA_MODEL`/`LEILA_LLAMA_BIN`.

## P0.09 — NobodyWho spike → build own `libleila_llm` (2026-11-02)

- Verified live on the RTX 4050 (NobodyWho v13.0.0 in a scratch Godot 4.7.2 project): json_schema
  grammar honors `maxLength`/enums/`additionalProperties:false` and preserves schema property
  order; `template_variables.enable_thinking`, `n_ctx` 8192, `context_shift`, penalties/seed all
  exist; per-token `next_token()` stream, warm ttft ~0.4 s.
- **No control vectors** (0 API methods; issue #40 open since 2024-11; llama-cpp-rs safe API has
  only `lora_adapter_set`) → per docs/07 §1's own rule we build the thin GDExtension. Windows GPU
  is Vulkan-only: 3.7–41.5 tok/s run-to-run (vs steady ~51 CUDA) and 5.7 GB VRAM vs 3.3 on server.
- Gotcha: headless fresh project needs `--import` once to register `.gdextension` files; nobodywho
  has no `n_gpu_layers`/device override and no `max_tokens` key. Their json_schema can emit stray
  props unless `additionalProperties:false` is set on EVERY object level (learned when beats[0]
  gained a `memory` key). One 995 s mid-JSON-truncated turn seen once, not reproduced.
- DCR filed: rename shipped extension `libqwenchan_llm` → `libleila_llm` (no brand names).
- Committed the test harness at `docs/spikes/p0.09_nobodywho_test/` (text only; addon DLL fetched
  per recipe). Scratch env at `D:/lila-wt/P0.09-scratch` is disposable.
