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
