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

## P1.06 PromptBuilder (round 1, deepseek)
- Built `game/autoload/PromptBuilder.gd`: `build(ctx) -> {messages, debug}`. docs/08 §1's eight layers
  (persona, player, stage, path, scene, memories, events, rules+glosses) join into ONE system message in
  that order; then history pairs (assistant turns as spoken text only), the current player turn, and an
  opt-in `ctx.prefill` block. Plus `spoken_text()`, `count_tokens()`/`estimate_tokens()`, `set_token_counter()`,
  `clear_cache()`. P1.08 builds `ctx`; P1.07 hands the offered enums in `ctx.offered`.
- Doc-silent choices, all tested: window = last 12 exchanges with pairs intact, then whole exchanges dropped
  from the oldest end past the ~1500-token budget; memories keep the newest 8; a missing stage/path file is
  reported in `debug.missing` and contributes nothing (never a silent stage-1 reuse); prefill OFF by default
  because llama-server's template already ends the prompt with the non-thinking assistant header.
- Budget report (P1.05 CON-1/DES-7): `debug.layers.<name>{tokens,chars,present,group,files}`, `tokens.fixed/
  dynamic/system_message/total`, `budgets` (docs/07 §3.1) and `over_budget`. Estimate `ceil(chars/3.6)`,
  calibrated on P1.05's real 857/873 and asserted within 5%; `set_token_counter()` takes the real one.
- Gotchas for P1.07/P1.08: gdlint caps a class at 20 public methods and counts `test_*` → history cases live in
  `test_prompt_builder_history.gd`; type test helpers by the preloaded script (`-> BuilderScript`) and annotate
  indexed results (`var messages: Array = …["messages"]`) or `:=` inference fails; never chain `assert_x(...)`
  with `override_failure_message(...)` across lines (parse error) — bind a local first.
- Goldens: `game/tests/fixtures/prompts/*.json`, cases in `tests/helpers/PromptGoldenCases.gd`, regenerate via
  `tests/tools/prompt_builder_goldens.gd`. A prompt-file edit now fails `test_goldens_match_…` on purpose.
- Measured: stage-1 loaded system message 990 estimated tokens (882 fixed + 108 dynamic) vs docs/07's ~900 line.
