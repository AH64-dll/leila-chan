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

## P1.08 (round 1, agent: gemini-3.8-flash)
- Implemented `Director.gd` (`game/autoload/Director.gd`) pipeline v1 wiring steps 0–7 of docs/02 §4: input handling, context assembly, PromptBuilder, TurnSchema, stage sampling/dose, IncrementalJson live event dispatch to AudioDirector, FX, SpriteResolver, Character, and ChatUI.
- Created `game/tests/DirectorTest.gd` testing full turn pipeline, recorded streams, cancellation, and memory validation.
- Verified full gate passes cleanly: gdlint, gdformat, godot headless tests (206 test cases, 0 failures), and pytest.
