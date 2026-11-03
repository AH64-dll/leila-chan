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

## P1.29 GameState hardening (round 2, follow-ups on P1.04 CODE-7..12 + DES-7)
- CODE-7: `_mood_suggest` → `_apply_mood_meter`; the budget now tracks LANDED movement
  (unlanded suggestions at a meter boundary no longer free budget in the opposite direction).
  Charged amount = the model delta clipped to the meter range, so a mid-turn ratchet lift
  (peak write) is never billed to the model's docs/01 §2 allowance.
- CODE-8: `version` dropped from `SNAPSHOT_KEYS` — a version-only dict is now rejected and
  cannot reset a live save. CODE-9: `instability_peak` has a clamping setter (direct writes
  bounded 0–100). CODE-10: `_is_json_safe(value, depth)` with FLAG_MAX_DEPTH=16 — cyclic/deep
  containers fail safely (no stack overflow). DES-7: non-finite floats (NAN/INF) rejected in
  flags AND at every meter choke point — `clampf()` passes NAN through, so `_clamp_meter()`
  now drops non-finite writes; `_num()` returns the fallback for NAN/INF snapshot input.
- CODE-11: `from_dict` sets peak + final stage BEFORE the meters, then emits one stage_changed —
  a load never flashes an intermediate stage. CODE-12: `state_reset` on a successful load is
  asserted exactly once (it already was emitted; the test was missing).
- Gotcha: a non-finite write can reach state only through the property setters, so the guard
  lives in `_clamp_meter()` (single choke point) rather than per setter. INF would otherwise
  land on a range bound the caller never asked for. Raw `instability_peak` pokes can still lift
  the floor without touching the meter; the next meter write snaps instability to the floor.
