# Raw SSE capture corpus — P1.02

Literal bytes captured from a real `llama-server`, for the transport (P1.02)
and the streaming parser (P1.03, whose current corpus is re-serialized Turn
objects — this directory is the literal-byte counterpart).

## What these files are

Each `.sse` file is the **response body** of one `POST /v1/chat/completions`
exactly as received, after HTTP chunked-transfer dechunking. Nothing was
re-serialized, pretty-printed or reordered: they still contain the leading
`data: {"choices":[{"delta":{"role":"assistant","content":null}}]}` event, one
event per content delta, the final event with `"delta":{}` and `"timings"`, and
`data: [DONE]`.

Provenance per fixture is in the matching `.meta.json` (full request, schema,
sampling, timings) and aggregated in `manifest.json`.

## Capture environment

| Item | Value |
|---|---|
| Captured | 2026-11-02, from the P1.02 worktree (`task/P1.02`) |
| Server | llama.cpp **b12024**, CUDA, `--jinja -ngl 99 -c 8192 -np 1` |
| Model | `Qwen3.5-4B-Q4_K_M.gguf` (2,740,937,888 bytes) |
| Client | `game/llm/backends/LlamaServerBackend.gd` via the LLM facade |
| Request | Turn-shaped `json_schema`, `stream: true`, `enable_thinking: false`, `cache_prompt: true` |
| Sampling | temperature 0.75, top_p 0.9, repeat_penalty 1.1, max_tokens 600 |

| Fixture | TTFT | First usable `say` | Full turn | SSE bytes | Delivered chunks |
|---|---|---|---|---|---|
| `p1.02_live_turn_01.sse` | 218 ms | 2041 ms | 4061 ms | 49862 | 181 |
| `p1.02_live_turn_02.sse` | 106 ms | 1854 ms | 3998 ms | 51223 | 186 |
| `p1.02_live_turn_03.sse` | 105 ms | 1798 ms | 3162 ms | 40638 | 147 |

Turn 1 paid for the cold server start; turns 2–3 reused the prompt cache
(`cache_n` 293, `prompt_n` 18/19). The `first_say` column is measured from the
POST, not from `generate()`, so all three columns exclude the ~4 s cold start.

## Regenerate

From the worktree root (needs the local model and binaries, see
`tools/llm/README.md`). This overwrites the `.sse`, `.meta.json` and merges
`manifest.json`:

```bash
tools/godot.ps1 --headless --path game res://tests/scenes/LlamaStreamDemo.tscn -- \
  --turns=3 --capture=game/tests/fixtures/sse --capture-turns=3 --quiet
```

## Use from P1.03

The backend feeds `IncrementalJson` the raw `choices[0].delta.content`
strings, not the SSE framing. Extract them from a fixture with:

```python
import json
chunks = []
for line in open("p1.02_live_turn_01.sse", encoding="utf-8"):
    if not line.startswith("data: ") or line.strip() == "data: [DONE]":
        continue
    event = json.loads(line[6:])
    content = event["choices"][0]["delta"].get("content")
    if content:
        chunks.append(content)
raw_json = "".join(chunks)   # the Turn JSON exactly as the model streamed it
```

The fixtures are UTF-8 and contain multi-byte characters only where the model
emitted them; split `chunks` at any byte or character boundary to exercise the
parser.

## Notes

- The `"model"` field in each event is llama-server echoing the documented
  local artifact path `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf`. It is not a user
  path and no secret is present.
- `created` is a server-side timestamp; the prompt cache and GPU state mean a
  rerun will not produce byte-identical output, only the same framing.
