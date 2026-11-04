# SYS journal — P2

## P2.26 — first-beat latency, measured (round 1, 2026-11-04, agent: commandcode)

- Built `tools/llm/latency_breakdown.py`: replays a transcript record's **own** request (messages + schema +
  sampling) against a llama-server and stamps one clock per landmark — headers, first token, first `say`
  character, first character the safety filter releases, turn end — plus the server's `timings`. Committed
  artifacts in `production/handoffs/media/P2.26/`. Convention: latency claims cite an artifact, never prose.
- The measured answer: pre-say **decode** is 72.6 % of the CPU first beat (48 tokens × 88.8 ms) and 76.4 % on
  CUDA (18.5 ms/token). Prefill 15.6 %/10.1 %, safety holdback 11.6 %/12.1 %, HTTP 0.2 %/1.3 %. Shipped order:
  5.92 s on screen (CPU) / 1.16 s (RTX 4050); cold KV: 13.2 s / 1.48 s. Reorder `music, fx, beats, read, inner…`
  → 4.47 s / 0.86 s, which clears the 1.0 s AC on CUDA (DCR-1, pending design review).
- Gotcha that decides every replay: `TranscriptLogger.gd:300` writes with `JSON.stringify`'s default
  `sort_keys=true`, so the stored `schema` is alphabetical and does **not** reproduce the wire request (the wire
  body uses `sort_keys=false`, `LlamaHttpClient.gd:152`). Rebuild the order from docs/02 §3; the control run with
  the sorted copy proves the model follows the *schema* order, not the prompt's ordering sentence.
- Gotcha for any future prompt work: `Safety._holdback` is **34 chars** (`max(_max_phrase+1)`, longest phrase
  "i want to sleep and never wake up"); `tools/test.sh` prints the same line. Any "first visible text" metric
  that omits it under-reports by 0.14 s (CUDA) / 0.69 s (CPU).
- Gotcha: a CPU-only extraction of llama.cpp starts happily with `-ngl 99` and silently decodes at 11 tok/s.
  Check `/proc/<pid>/maps` for `libggml-cuda`; the CUDA 13.4 build (fetched to `tools/llama/llama-b12024-cuda/`,
  gitignored) gives 54 tok/s on the RTX 4050. Do **not** try to fix CPU speed with `-t`: 12 threads on 6 cores
  measured 2.4–6.9× slower.
- Gotcha: the first beat of a session pays the whole 986-token prefill (8.6 s CPU / 0.46 s CUDA); mid-session,
  `prompt_n` spikes to 1298–1449 whenever a **memory fact** lands, because `memories` sits before `rules` and the
  history in docs/08 §1's layout (DCR-2). Metric to watch in future prompt work: `prompt_n` per turn, and the
  longest common prefix between consecutive prompts.
