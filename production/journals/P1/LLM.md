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

## P1.27 — P1.01 review follow-ups: facade error normalization, cancel race, stream contract (2026-11-03)

- Normalized backend error returns in `LLM.gd`: require `error.get("code") is String` (defaulting `message` to `""` if missing/non-string), otherwise fallback to `malformed_result`.
- Fixed worker-return vs deferred terminal delivery race (DES-3): `_deliver_terminal` checks `stream._cancel_token.is_cancelled()`, ensuring cancellation wins over completion or failure.
- Documented single-use `TurnRequest` ownership in `TurnRequest.gd`, `LLM.gd`, and `docs/07_TECH_ARCHITECTURE.md§3.1`.
- Corrected stale facade signature in `docs/07_TECH_ARCHITECTURE.md§2` (`generate(TurnRequest)`) and documented helper APIs + standard error vocabulary in §3.1.
- Added regression tests covering malformed error dicts and cancellation between worker return and terminal delivery (both clean completion and error paths); 14/14 LLMTest cases pass.
