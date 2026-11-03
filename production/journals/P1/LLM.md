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

## P1.03 IncrementalJson (round 1, swe2)
- Built `game/llm/IncrementalJson.gd`: RefCounted char-fed state machine; `feed() -> Array[Dictionary]` events
  (field / beat_start / beat_field / say_chunk / error), `finish() -> Status` (OK/TRUNCATED/ERROR), `get_value()`
  mirrors JSON.parse. Transport-free per playbook — P1.02's backend wraps it, do NOT add HTTP here.
- Conventions I fixed (doc open, see class docstring): mood = one field event at close; beats has no field
  event; say chunks + a closing beat_field(i,"say",full); int for integral numbers (Godot JSON.parse → float);
  pending unterminated tokens commit nothing at finish.
- Corpus: `tools/llm/make_stream_fixtures.py` re-serialises recorded `out` objects from
  experiments/results_v3.json + experiments/windows/tool_test_v3.json → 75 fixtures + manifest (recorded
  replies, not literal byte streams — experiments never captured them). Synthetic fixtures cover what
  recordings lack: escapes incl. split `\"`, unicode literal + `\uXXXX` + surrogate pair.
- Gotchas: gdlint enum names may NOT start with `_` (ParseState/ContainerRole, not _St/_Role); project treats
  `var x := variant` inference as error — annotate `var top: Dictionary = _stack.back()`; max-returns 6 →
  if/elif chains, not early returns; `say` text split mid-escape needs `_esc`/`_high` pending state kept in
  instance vars, never local. Empty `[]` needs the `]`-in-VALUE-with-empty-array branch.

## P1.03 IncrementalJson (round 2, swe2)
- Error contract: flush decoded say before `error`; `error` is last. Whole vs per-character broken-say feeds give identical sequences (offset 155).
- `get_value()` on TRUNCATED/ERROR = outermost completed container via `_has_root`, null before a root opens; partial say is events-only.
- Empty say = no chunk, only `beat_field(i,"say","")`; `synth_empty_say.json` + oracle skip + explicit test.
- Corpus 75 recorded + 5 synthetic = 80; escapes 4 recorded + 2 synthetic. Don't overstate counts.
- DCR-1 (docs/07 §3.2 payload table + docs/02 step-5 no-replay note) is in handoff Round 2; producer decides.

## P1.07 TurnSchema (round 1, gemini-3.8-flash)
- Built `game/llm/TurnSchema.gd` with stage-gate data table `game/data/stage_gates.json` and canonical feelings from `game/data/casting.json`.
- Implemented `build_turn_schema(ctx, offered_actions)` producing llama-server json_schema with canonical property order (`read`, `inner`, `beats`, `mood`, `memory`, `action`, `music`, `fx`, `meta`), stage gates across 0–5, `meta` null/gated for stages 0–2 vs unlocked at 3+, and C9 minLength:1 on `inner`/`say`.
- Provided semantic validation helper `validate_turn(turn, stage, offered_actions, options)` for Director and test suites.
- Tests: `game/tests/TurnSchemaTest.gd` with 15 gdUnit4 cases covering schema structure, stages 0–5 enums and gates, meta gating, action offers, string limits, mood bounds, and data loading.
