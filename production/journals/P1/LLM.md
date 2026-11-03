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

## P1.23 — P0 gate C1: drive-colon handling for cvec launch paths (2026-11-03)

- Verified on the pinned binary: `--control-vector-scaled` splits on ':'/',' and needs exactly two
  fields, so `D:/v.gguf:4` is rejected outright ("FNAME:SCALE" error) — no spelling of a colon path works.
- Fix: shared `tools/llm/cvec_path.py` (normalizer + scale validation, `flag_arg()`); both launchers
  shell out to it, steer_sweep.py imports it. `X:/...` → same-drive relative path (cwd-bound);
  `X:file`, cross-drive, ':'/',' in names → clear error. New flags: `serve.sh --dry-run`, `ps1 -DryRun`.
- Gotcha: tests on Linux emulate Windows via `--platform windows`/`ntpath`; Git Bash must `cygpath -w`
  paths before calling python. `$VectorScale.ToString(InvariantCulture)` — `,` decimal cultures break F:S.
- `LlamaServerProcess.gd` (P1.02) has the same `%s:%s` construction — reuse this rule in P2.03.
