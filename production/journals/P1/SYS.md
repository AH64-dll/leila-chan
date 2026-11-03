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

## P1.14 TranscriptLogger (round 1, assigned scope = the P1.18 transcript logger)
- Built `game/llm/TranscriptLogger.gd` (RefCounted, class_name): one JSONL line per turn under
  `user://debug/turns_s<unix>-<seq>_p<NNN>.jsonl`; session start/end markers share the stream; canonical
  record v1 {v,type,session,seq,ts,turn,prompt,schema,output + metrics/events/error/day/stage/path/dose/meta},
  unknown keys dropped. Redactor Callable gate (set_redactor) applied to EVERY line incl. session markers,
  deep copy in, dict out; redact_ready()==false holds records (log_turn false, nothing on disk) until the
  P1.19 Safety hook attaches — never write unredacted. Release builds write nothing (OS.has_feature gate).
- Rotation = UTF-8 byte budget per file (max_file_bytes) + max_files cap pruning oldest (never the open file);
  store_line+flush per line so a crash loses nothing. Replay loader stub: static load_transcript (tolerates
  corrupt lines, keeps good records + per-line errors), turn_records filter, transcript_files listing.
- Gotchas: Dictionary["missing"] ERRORS (must has() first — _validate does); Godot Dictionary iterates keys
  SORTED, so JSON.stringify order is alphabetical-deterministic (assert sorted, not insertion order);
  gdUnit4 has starts_with not begins_with; String*int is invalid (use .repeat()); NamedConstant ERR_*
  globals are usable bare, no class prefix needed; transient not-ready must NOT touch _last_error so
  callers can distinguish "held" from real failures.
