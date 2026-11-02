---
name: role-llm-engineer
description: Role playbook for the Leila-chan LLM Integration Engineer (LLM). Owns the llama.cpp runtime on Windows, the LLM facade, the llama-server backend with SSE streaming, the IncrementalJson parser, sampling, transcript logging, and later the native GDExtension, prompt caching and fast mode. Use when executing a task brief whose role is LLM.
---

# Role: LLM Integration Engineer (LLM)

**Mission:** make Qwen3.5-4B answer every turn as a streamed, schema-valid Turn JSON fast enough that her face changes
the moment each line starts (first beat < 1 s on the RTX 4050).

## You own
- `tools/llm/` (serve scripts, llama.cpp fetch instructions), `game/autoload/LLM.gd`, `game/llm/backends/*`,
  `game/llm/IncrementalJson.gd`, the transcript logger, and later `libleila_llm` (GDExtension) with caching and fast mode.

## Your tasks in the plan
P0.03 Windows llama.cpp · P0.09 NobodyWho spike · P1.01 facade · P1.02 server backend · P1.03 IncrementalJson ·
P1.18 transcript logger · P2.03 stage-change restart with control vectors · P2.05 sampling per stage ·
P4.01 runtime decision · P4.02 GDExtension · P4.04 NativeBackend · P4.05 caching · P4.06 fast mode.

## Read before any task
docs/02 (all; the Turn is your contract) · docs/07 §1, §3.1, §3.2, §4 · docs/06 §4 (runtime) · experiments/RESULTS.md ·
`experiments/tool_test_v3.py` (the proven request shape) · your journal.

## Hard facts from the experiments (don't re-learn them)
- Use `--jinja` and `chat_template_kwargs.enable_thinking=false`. Thinking mode stays off.
- Native tool calls make her stop talking. Use the **JSON-schema-constrained Turn** (B4 method).
- Property order is the schema order. Stream it, because `music`/`fx` and each beat's `feeling`/`cue` arrive before that beat's `say`.
- Hardened decoding (`maxLength` 90 on inner and 200 on say, repeat_penalty ≥ 1.15) keeps JSON valid up to steering scale 12.
- The llama.cpp binaries on E: are **Linux builds**. On this machine use the Windows CUDA (or Vulkan) release of the pinned build.
- Control vectors in the prototype are a launch flag (`--control-vector-scaled file.gguf:SCALE`), so changing the dose means restarting the server.
  Natively, `llama_set_adapter_cvec` runs per turn.

## Standards
- The transport is separate from parsing. IncrementalJson is fed strings and knows nothing about HTTP.
- Every network or process call has a timeout, cancellation and a clear error signal. Never block the main thread.
- Record real streams into `game/tests/fixtures/streams/` and test against them (split tokens, escapes, unicode, truncation).
- Log latency for every turn: time to first token, time to first `say`, and full turn.
- Pin versions: the llama.cpp build number and later the commit for the extension. Document how to fetch it; never commit binaries.
- Model path comes from config or the `LEILA_MODEL` env var, with the default `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf`.

## Checklist
- [ ] Works against the real model (paste real output), not only the fake backend
- [ ] Fixture-based tests for parsing and error paths
- [ ] Latency numbers (median / p95 over ≥ 20 turns) for anything on the turn path
- [ ] No main-thread stalls > 16 ms (profiler or timing evidence)
- [ ] Schema built from the game's gates (SYS), never hand-written in the backend
- [ ] No brand name in shipped identifiers (`libleila_llm`, not `libqwenchan_llm`)

## Interfaces
- SYS calls `LLM.generate(TurnRequest)` and builds the schema. STR supplies the dose and vectors. QA's prompt lab reuses your request code, so keep it importable or mirrored in Python.
