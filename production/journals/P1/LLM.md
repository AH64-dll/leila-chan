# LLM journal — phase P1

## P1.01 — LLM.gd facade: TurnRequest/TurnStream, worker thread, cancel (2026-11-02)

- Facade per docs/07 §3.1: `TurnRequest{messages,schema,sampling,dose,max_tokens}`, `TurnStream`
  (`token`/`completed`/`cancelled`/`failed` — one terminal ever), `LLMCancelToken`, `LLMBackend`
  contract `generate(request, on_token, cancel) -> {ok,text}|{ok,error:{code,message}}`.
- 1 `Thread` per turn; all emissions relayed via `call_deferred`; joins only after `is_alive()==false`;
  `_shutdown` cancels+joins on PREDELETE. `set_dose` fills empty `request.dose` at generate.
- Conventions chosen (doc silent): immediate fails (`busy`/`no_backend`/`invalid_request`/`thread_error`)
  still emit `failed` deferred; `_active` cleared before terminal emit → reentrant `generate()` works.
- Gotcha: gdformat strips `()` from zero-arg signals. Tests: `helpers/FakeLLMBackend.gd`
  (`block_until_cancel`, `worker_thread_id`) — 11 cases green.
- Next: P1.02 LlamaServerBackend implements the contract + wires the autoload default.

## P1.02 — LlamaServerBackend: HTTP/SSE, schema per request, timeouts, restart (2026-11-02)

- Built `LlamaHttpClient` (raw TCP HTTP/1.1, chunked/Content-Length/close, byte-safe SSE,
  `[DONE]`, timings, capture), `LlamaServerProcess` (attach/start/stop/restart + `/health`), and
  `LlamaServerBackend` (request body, metrics, retry-once, watchdog). `Boot.gd` installs the
  attach-mode default; `LLM.use_default_backend(config)` is the entry point.
- Conventions (doc silent): whitelisted sampling with 0.8/0.9/1.15 defaults; non-empty
  `request.schema` required; `cache_prompt=true`; auto-watchdog only for an owned process;
  attach-mode never kills; retry only before the first token; `first_say` from the POST, startup
  separately as `ready_ms`.
- Gotchas: gdUnit treats inferred Variant warnings as parse errors (`var x := await f()` must be
  typed); `HTTPRequest` cannot run on the worker, so raw `StreamPeerTCP` is mandatory; fake
  servers must answer `GET /health` or attach-mode looks like `port_in_use`.
- Real numbers on the 4050: TTFT median 94–102 ms/p95 117 ms; first usable `say` median 1.81–1.86 s,
  p95 2.02–2.60 s (19–20/20; empty `say` = n/a); full turn 3.3–3.7 s median. Crash restart 2.4–3.0 s.
- Next: P1.03 consumes the literal SSE fixtures and replaces `FirstSayProbe`; P1.07 adds non-empty
  `say`; P2.03 maps `request.dose` to control vectors and restarts at stage changes.
