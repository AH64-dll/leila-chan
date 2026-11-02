# fixtures/streams — recorded Turn streams for IncrementalJson tests (P1.03)

`turn_*.json` are the model's real replies, recorded non-streamed by the
experiment harness and re-serialised verbatim to the compact JSON a
llama-server token stream would carry. They are recorded model outputs, not
literal captured SSE bytes (P1.02 owns the literal stream corpus).
`synth_*.json` are hand-built to cover what the recordings lack (escape
sequences, literal UTF-8, `\uXXXX` escapes incl. a surrogate pair, and an
empty `say` per docs/02 §7). `manifest.json` records provenance and flags.

- Sources: `experiments/results_v3.json` (30 turns, stages 0+4),
  `experiments/windows/tool_test_v3.json` (45 turns — the Windows run).
- Regenerate: `python tools/llm/make_stream_fixtures.py`
- Consumers: `game/tests/IncrementalJsonTest.gd`
