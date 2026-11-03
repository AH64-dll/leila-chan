# SYS journal — P1

## P1.04 GameState (round 1, done)
- Built GameState.gd: 5 meters via clamping property setters, ratchet floor = peak−15, monotonic stage
  (interpretation — docs silent; flagged in handoff), day/turn/path/flags, 12 profile counters,
  to_dict/from_dict with healing. read→counter map is DATA at game/data/profile_map.json (+tone map
  for inconsistency swings); control/apathy come from classifier rules via bump_profile().
- Conventions: meters are float + StringName keys; profile/flags keyed by String for JSON safety;
  model input only via apply_mood/apply_read; signals fire on every real change (overlay-ready).
- Gotchas: property setters run during member init → declare instability_peak/stage BEFORE instability.
  gdUnit4 counts each test_* toward max-public-methods:20 and Variant receivers need explicit types.
  gdtoolkit rejects multi-line match patterns — used a const type array instead. JSON normalises ints
  to floats inside flags; the round-trip test compares in the JSON domain.

## P1.04 GameState (round 2, reworked after code+design reviews)
- from_dict now rebuilds on a canonical baseline (instance-independent): peak clamped 0–100, stage =
  band(instability_peak) — the stored stage is only cross-checked, never trusted. PATHS are the
  uppercase casting.json ids (TSUN, not TSUN-BREAK).
- Per-turn mood budget: `_mood_suggest` clamps the running total per meter in `_mood_spent`, reset on
  `turn` change — "±5/±3 per turn" is a budget, not a per-call cap. Flags validate recursively.
- reset() and from_dict() end with a single `state_reset` signal — the resync contract for UI/overlay,
  cheaper than replaying every per-field signal.
- Gotchas: `stage` setter can't emit (fires during member init before connections) — bulk changes
  signal via state_reset or an explicit stage_changed. Keep test_* count ≤20/suite (gdlint
  max-public-methods); split restore regressions into GameStateRestoreTest.gd.

## P1.07 TurnSchema (round 1, gemini-3.8-flash)
- Built `game/llm/TurnSchema.gd` and autoload shim `game/autoload/TurnSchema.gd` with data tables in `game/data/stage_gates.json`.
- Dynamic schema builds per-turn json_schema adhering to canonical property order: `read, inner, beats, mood, memory, action, music, fx, meta`.
- Gates enforced across stages 0–5: `meta` null/gated for 0–2 vs unlocked object/null at 3+; C9 `inner` and `say` minLength:1.
- `validate_turn()` provides runtime validation for Director and tests.
- Gotchas: Godot's GDScript parser treats `var x := variant` inference as a hard compilation error under strict warnings — always explicitly type `var cues: Array = ...`.
