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
