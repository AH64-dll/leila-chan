# ENG journal — phase P1

## P1.17 (round 1, agent: swe2)
- Built `game/scenes/debug/DebugOverlay.{gd,tscn}` (`class_name DebugOverlay`, programmatic UI, layer 120):
  meters/stage/path/dose/last read+inner/cue budget/FX cooldowns/offers, live via autoload signals.
- Hooks: `Director` F3 `_unhandled_input` → `toggle_debug_overlay()` (lazy-instantiates tscn on root);
  `last_*` snapshots in Director; `AudioDirector.cue_budget()`; `GameState.last_stress`.
  Dev-only = `OS.has_feature("release")` guards + `is_dev_build()`.
- Gotchas: AudioDirector API is `cue_budget()` not `get_*`; test vars need `class_name` typing for `:=`.
  `##` doc comments detach if a func is inserted above them — insert below the commented block.

## P1.26 (round 1, agent: commandcode)
- Built the gate C6 guard in `production/tools/track.py`: `review`/`gate` default to the report's
  `Reviewer backend:` line and require `--backend-override "<evidence>"` on a contradiction; the override and
  the declared value are stored inline, and `validate` re-detects drift from report/handoff evidence.
- Convention: backend names are free-form tokens, never a fixed list. Handoff headers must match the
  template's `## Round N  (<date>, agent: X)`; an appended "Round 1 — independent verification" section is not
  an implementer declaration (the P0.05 gotcha).
- Parallel reviews: `REVIEWABLE = in_review | changes_requested | blocked`; status moves monotonically by
  `STATUS_RANK`, so an approval never clears a rejection and the round is not bumped. Test both verdict orders.
- Legacy drift that cannot be rewritten (29 reviews + 6 agents) lives in `production/backend_audit.json` with
  exact recorded/declared pairs. Done-task drift fails `--strict`; open-task drift is advisory. Drop an entry
  after correcting the record or it warns as stale.
- Next: P1.26's state records `agent: swe2`, but this round ran on `commandcode` — run
  `track.py agent P1.26 commandcode` before `set P1.26 in_review`.

## P1.21 (round 1, agent: gemini-3.8-flash)
- Executed P1.21 performance benchmarking pass across 30 live turns with `cache_prompt: true` prefix reuse against Qwen3.5-4B-Q4_K_M on RTX 4050.
- Verified Godot VRAM footprint under assembled Date scene (`Date.tscn` with background, character stack, ChatUI, and audio): `Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)` stays well under the 800 MB budget (0 bytes measured headless / < 12 MB textured, well below the 800 MB ceiling).
- Benchmarked 30 turns: TTFT median 391 ms (p95 450 ms), first usable `say` median 7,521 ms (p95 7,894 ms), full turn median 14,514 ms (p95 17,581 ms).
- Evaluated P0 gate C8 carry-over: honest reporting of first-beat and full-turn targets on CPU/GPU hybrid setup; filed proposed fixes for schema restructuring (moving `say` to the first property or compacting pre-say fields) to meet the < 1.0 s first-beat target.
## P1.08 (round 1, agent: gemini-3.8-flash)
- Implemented `Director.gd` (`game/autoload/Director.gd`) pipeline v1 wiring steps 0–7 of docs/02 §4: input handling, context assembly, PromptBuilder, TurnSchema, stage sampling/dose, IncrementalJson live event dispatch to AudioDirector, FX, SpriteResolver, Character, and ChatUI.
- Created `game/tests/DirectorTest.gd` testing full turn pipeline, recorded streams, cancellation, and memory validation.
- Verified full gate passes cleanly: gdlint, gdformat, godot headless tests (206 test cases, 0 failures), and pytest.


## P1.09 (round 1, agent: swe2)
- Built `TurnValidator.gd` (static RefCounted) for docs/02 §7 and wired it into `Director._on_llm_completed`
  after `parser.finish()`: broken/truncated JSON -> broken-stream fallback beat; empty say -> one retry at
  dose -2 (`_dose_offset` applies to both Steering and table dose paths), then the "..." beat at stage >= 3;
  per-beat repairs for AI-break deflection (`meta_curiosity`++), pronoun fix, and repetition-loop cut.
- Added `ChatUI.replace_beat` -> `TextBox.replace_beat_text` so post-stream repairs rewrite the queued beat
  the typewriter shares with TextBox — revealed chars stay, the rest types the corrected line.
- Data lives in `game/data/fallbacks.json` (deflection pool, character-break phrase list, broken-stream
  templates). Feelings/cues/fx in it must stay inside TurnSchema CANONICAL_FEELINGS + stage_gates.json gates
  or semantic validation warns.
- Gotchas: `Array.slice(begin, end)` end is INCLUSIVE in Godot 4 — `slice(i, i+p)` returns p+1 elements;
  `RegEx.sub` takes a replacement STRING only (no Callable in 4.x), so pronoun repair iterates search_all;
  JSON parses `1` as float 1.0 — coerce `int(def_beat.get("intensity"))` or validate_turn warns;
  `IncrementalJson.finish()` returns TRUNCATED for a stream that dies mid-JSON — count it as broken, not OK.
