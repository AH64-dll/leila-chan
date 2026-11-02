# LLM journal — P1

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
