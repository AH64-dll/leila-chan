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

**Check the offload is real (P2.26 gotcha).** A CPU-only extraction starts
happily with `-ngl 99` and then decodes at ~11 tok/s; nothing fails.

```bash
grep -o '[^/ ]*ggml-cuda[^ ]*' /proc/$(pgrep -f "llama-server.*-m") /maps 2>/dev/null || true
```

An empty result means the CUDA backend is not loaded — re-fetch with
`--variant cuda-13.4` (the Linux tarballs extract into a nested
`llama-b12024/` directory, and the cudart tarball into its own). On this
machine the CUDA build lives in `tools/llama/llama-b12024-cuda/`, and a
6-thread CPU server measures 11 tok/s vs 54 tok/s with `-ngl 99`.

### 3.1 First-beat latency breakdown (`latency_breakdown.py`, P2.26)

```bash
# replay the prompts a real date sent, per-landmark timings + server timings
python3 tools/llm/latency_breakdown.py --session 1 --turns 0:6 \
    --url http://127.0.0.1:8089 --order docs --out /tmp/beat.json
```

It reads the transcript logger's records (`production/playtests/*/transcripts`)
and re-sends each turn's `prompt` + `schema`, timestamping the HTTP round trip,
the first token, the first `say` character, the first character `Safety` lets
through, and the end of the turn, plus the server's own `timings`. The
"visible" landmark models `Safety._drain`: the filter holds 34 characters of the
**separator-free compact view** (`SafetyText.compact`), so a phrase prefix padded
with spaces or punctuation buys no emission budget and the first character can
appear after more raw characters than the holdback. The table prints that
optimistic raw-char landmark as `R` beside it; the holdback is derived from
`game/data/safety/filter_lists.json` (longest phrase + 1) and pinned by a test.
The `say` body is decoded as the SSE deltas arrive, and an escaped quote inside
it is content, not the closing quote.

`--order beats_first|say_first|music_fx_beats_first|alphabetical` replays a
*reordered* schema (measurement only — the shipped order is docs/02 §3), and
`--system-order` also rewrites the ordering sentence **and** the field list
under it. Both are CRLF in `rules.md`, so the needle accepts `\r?\n`; a
bare-`\n` needle patched nothing on all 39 recorded prompts. `--no-cache` forces
a cold KV. Every artifact records the run config it was produced with (`order`,
`system_order`, `cache_prompt`, the sampling sent per row), so it can be
reproduced from itself.

The transcript's stored `schema` copy is alphabetical (`JSON.stringify`'s
default `sort_keys=true` in `TranscriptLogger.gd:300`), so the harness restores
the wire order itself; never replay that copy as-is.

## 4. Game transport: `LlamaServerBackend` (P1.02)

`game/llm/backends/LlamaServerBackend.gd` implements the `LLMBackend`
contract on the facade's worker thread. It speaks HTTP/1.1 + SSE over
`StreamPeerTCP` (Godot's `HTTPRequest` is a Node and main-thread only), sends
**the request's own** `json_schema` as `response_format`, passes sampling and
`max_tokens`, forces `enable_thinking=false`, and never blocks the main thread.

Two modes, selected by `auto_start`:

| Mode | Config | Behaviour |
|---|---|---|
| attach (default) | `base_url` only | Talks to a server you started with `serve.ps1`/`serve.sh`. Never launches or kills anything. A healthy server on the URL is adopted. |
| start | `auto_start=true`, `server_exe`, `model_path` | Launches the pinned binary with `--jinja -ngl 99 -c 8192 -np 1` and any `control_vectors`, then waits for `/health`. If the port already answers, the existing server is adopted instead of starting a second one. |

`game/autoload/LLM.gd` exposes `use_default_backend(config)`; `Boot.gd` installs
the attach-mode default. A boot scene that should own the process calls
`LLM.use_default_backend({"auto_start": true})` once.

Key config (defaults in `LlamaServerProcess.default_config()`):

| Key | Default | Meaning |
|---|---|---|
| `base_url` | `http://127.0.0.1:8089` | Server root (a full `/v1/chat/completions` URL is accepted) |
| `chat_path` | `/v1/chat/completions` | Appended to `base_url` |
| `auto_start` | `false` | Launch and supervise our own process |
| `watchdog` | `true` | Auto-start supervision when we own the process |
| `watchdog_interval_ms` | 1000 | Liveness check interval (crash restart measured 2.4–3.0 s) |
| `server_exe` | `$LEILA_LLAMA_DIR/llama-server(.exe)`, else `D:/lila/tools/llama/llama-b12024/...` | Pinned binary |
| `model_path` | `$LEILA_MODEL`, else `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf` | GGUF |
| `control_vectors` | `[]` | `[{"path": "...gguf", "scale": 4.0}]`, launch flags (docs/06 §4) |
| `connect_timeout_ms` | 2000 | TCP connect |
| `read_timeout_ms` | 60000 | Max idle between socket reads |
| `turn_timeout_ms` | 180000 | Hard cap for one request |
| `startup_timeout_ms` | 30000 | `/health` wait after launch |
| `retry_once` | `true` | One retry, before any token, on a transport failure |

Supervision: when the backend owns the process it auto-starts a watchdog
(`watchdog=true`) that checks the process every interval and restarts a dead
one; on this machine a crash → healthy restart measured **2.4–3.0 s** (P1.02
live test). Attached servers are never restarted. `shutdown()` stops the
watchdog and our process; the LLM autoload calls it after joining the worker.

Each turn logs one line and keeps the same numbers in `last_metrics()`:

```
[LlamaServerBackend] turn ok ttft=102ms first_say=1830ms total=3302ms ready=3ms chunks=141 pid=25556 restarts=0
```

`ttft` and `first_say` are measured from the POST, so a cold server start is
reported separately as `ready_ms`/`server_startup_ms`. `first_say` is the first
character of the first non-empty `say` value; it is not the same as TTFT
(P0 gate C8).

### Verify against the real server

```bash
# one turn: prints every raw chunk + ttft/first_say/total
tools/godot.ps1 --headless --path game res://tests/scenes/LlamaStreamDemo.tscn -- --turns=1

# 20-turn latency table (median/p95) and literal SSE capture
tools/godot.ps1 --headless --path game res://tests/scenes/LlamaStreamDemo.tscn -- \
  --turns=20 --capture=game/tests/fixtures/sse --capture-turns=3 --quiet

# live gdUnit suite: schema-per-request, crash restart < 5 s, first say
tools/godot.ps1 --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/LlamaServerLiveTest.gd -c --ignoreHeadlessMode
```

The live suite skips when the local model/binaries are absent; the demo and
capture need them. The captured corpus and its provenance are documented in
`game/tests/fixtures/sse/README.md`.
