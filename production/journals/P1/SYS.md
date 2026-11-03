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


## P1.09 Validation & fallbacks (round 1, swe2)
- Implemented `game/autoload/TurnValidator.gd` + `game/data/fallbacks.json` for docs/02 §7: broken JSON,
  empty say, repetition loop, pronoun repair, early AI-break deflection. `Director` dispatches all of them
  at turn close (`_on_llm_completed`), per §4 step 6.
- Convention: turn-content pools/phrases are data (`res://data/fallbacks.json`), never code literals; the
  validator is a static RefCounted reached via class_name, same pattern as TurnSchema.
- Handling effects reach the screen via the new `ChatUI.replace_beat` -> `TextBox.replace_beat_text`
  (the Typewriter shares TextBox's beat dicts); repairs mutate turn_data before `_close_turn_success`.
- Empty say: stage < 3 retries once at dose -2 — applied to BOTH Steering and table dose (`_dose_offset`);
  stage >= 3 (or a failed retry) gets the "..." beat so the turn still closes cleanly.
- Gotchas: `IncrementalJson.finish()` -> TRUNCATED on a dead stream (treat as broken JSON); `Array.slice`
  end index is inclusive; `RegEx.sub` accepts only string replacements; JSON ints parse as floats.
- Not built (flagged in handoff): the literal "glitch filter" pass over partial say (fx glitch + text
  level is what exists), and the "typing indicator stuck for 3 s" is simplified to an immediate "..." close.

## P1.09 Validation & fallbacks (round 2, deepseek)
- Reworked per P1.09 r1 reviews (DES-1/2/3, CODE-1/3/4). `Director.META_WORDS` narrowed to the
  prompt-lab-proven explicit-meta list (player, stage, json, schema, enum, prompt, label(s), request,
  response, jealousy_bait, small_talk) so the stage-0 few-shot's own `gave me a music box` is stored —
  a literal schema-key list was the P1.05 CON-2 trap. Keep this list in step with `tools/promptlab/lab.py`
  (P1.20 owns extracting it to `game/data/`).
- Pronoun repair now gates on "no other male referent": `TurnValidator.has_other_male_referent` scans the
  say + the last 3 player messages against `male_referent_names` in `game/data/fallbacks.json`. It also
  re-conjugates the verb (`He is`->`You are`, `He never listens`->`You never listen`); when no verb can be
  safely adjusted it leaves the sentence alone and warns instead of emitting broken grammar.
- Filter-once invariant: the `say_chunk` fallback paths now pass RAW text like `replace_beat` does — the UI
  seam (`ChatUI.text_filter`) is the only place model text is scanned. Never pre-filter at a Director callsite.
- gdlint caps a suite at 20 public methods: the §7 integration tests live in the new
  `game/tests/DirectorFallbackTest.gd` (DirectorTest keeps steps 0-7, memory, transcript/replay).
  `FakeLLMBackend.chunk_sets` scripts per-call chunk streams so one turn can generate twice (the retry).
- Gotchas: stage-0's table dose is 0.0 so `dose_dict` is EMPTY there — assert the retry arithmetic at
  stage 1 (2.5-2.0=0.5) and the clamp separately; consts must precede static vars or gdlint
  `class-definitions-order` fails; `git merge main` brought a stale P1.09 snapshot in via the P1.21 merge
  (non-canonical feelings, strict 4-gram) — this branch's version is the reviewed one.

## P1.07 TurnSchema (round 1, gemini-3.8-flash)
- Built `game/llm/TurnSchema.gd` and autoload shim `game/autoload/TurnSchema.gd` with data tables in `game/data/stage_gates.json`.
- Dynamic schema builds per-turn json_schema adhering to canonical property order: `read, inner, beats, mood, memory, action, music, fx, meta`.
- Gates enforced across stages 0–5: `meta` null/gated for 0–2 vs unlocked object/null at 3+; C9 `inner` and `say` minLength:1.
- `validate_turn()` provides runtime validation for Director and tests.
- Gotchas: Godot's GDScript parser treats `var x := variant` inference as a hard compilation error under strict warnings — always explicitly type `var cues: Array = ...`.

## P1.18 — TranscriptLogger integration & replay stub (2026-11-03, agent: gemini-3.8-flash)

- Integrated `TranscriptLogger` into `Director.gd` (`director.transcript_logger`): every completed, failed, and cancelled turn logs canonical turn record {prompt, schema, raw output, applied events, metrics, stage, path, dose, day, meta} to `user://debug/` JSONL.
- Added `LLM.get_backend()` and `LLM.last_metrics()` facade pass-through to retrieve backend performance timings (`ready_ms`, `first_token_ms`, `generate_ms`).
- Safety redaction wired via `transcript_logger.set_redactor(Callable(self, "_redact_record"))`: integrates `Safety.redact_record` when available and falls back to `filter_output`.
- Implemented `replay_turn(turn_record: Dictionary) -> bool` on `Director`: feeds transcript records through `IncrementalJson` and dispatches events end-to-end to subsystems and GameState.
- Tests in `DirectorTest.gd`: verified logging on completion, failure, cancellation, safety redaction, and end-to-end transcript replay.

## P1.08 round 2 — Director rework: safety seam, single-resolution beats, split units (2026-11-03, agent: deepseek)

- Rebound the docs/02 §8 safety path to the P1.19 filter's streaming API (`begin_say`/`say_chunk`/`end_say`) via the new `SaySafetyGate`: the Director owns the beat boundary and never installs `ChatUI.text_filter`, so nothing scans a chunk twice. Fail-closed: no filter → redaction bars, never raw text.
- Split Director.gd (was 1111 lines / 23 public methods, over both gdlint caps) into four seams the review exposed: `SaySafetyGate` (scan), `MemoryRules` (§6), `TurnContext` (ctx + docs/02 §9 sampling from data), `TurnFallback` (§7 shapes). Keep new pipeline logic in one of these, not in Director.gd — the file sits at 20 public methods, exactly the cap.
- One resolver pass per beat: `Director` resolves, emits `beat_resolved`, notes the sprite on AudioDirector, and hands the packet to the new `Character.apply_beat(packet)`. Never call `set_feeling` from the Director — the resolver's anti-repeat window is stateful and double-resolves.
- `_teardown_turn()` is the only turn exit (completed/failed/cancelled). Gotcha: write the transcript record BEFORE teardown, since the record is built from the turn-scoped context the teardown clears.
- Gotcha for the next SYS task: `read`/`write` relative paths in this worktree resolve against the MAIN tree, not the worktree. Use absolute worktree paths (the `lila-wt/<task>` root), or new files land in main.

## P1.31 — gate-r1 remediation: an unsafe player line must not deadlock the chat UI (2026-11-04, agent: commandcode)

- Step 0.1 rejection is now a real turn exit: `Director._reject_unsafe_input()` writes the failed record (`unsafe_input`) and answers with one in-fiction refusal beat, instead of `turn_failed.emit()` + bare `return false` (the F3 lockup: submit had already called `ChatUI.begin_turn_wait()`, so `input_enabled` stayed false and the dots stayed up forever).
- Seam choice: the UI owns its own release. `ChatUI.reject_turn(text)` resets the box, queues the refusal as beat 0 (`begin_beat` → `replace_beat` → `end_beat`) and calls `end_turn()`, so the ordinary reveal-then-`_maybe_close_turn` path unlocks the input — same as a reply, no new signal, no `abort_turn` wipe of the refusal.
- The refusal is content, not code: `game/data/fallbacks.json` → `unsafe_input_fallbacks` (stage 0–2 nervous / stage 3+ cold), read by `TurnValidator.get_input_refusal(stage, player_name)`. Cue is `"none"` on purpose — an input rejection must not spend the docs/02 §5 cue budget (AudioDirector's per-turn counters are only reset by a real turn).
- Filter-once still holds: the Director scans the refusal through `SaySafetyGate.filter_text` before the UI sees it (production's `ChatUI.text_filter` is Date's pass-through), and calls `_safety.end_utterance()` first so the previous reply's tail cannot glue onto the refusal.
- The rejected line never enters `history`/`last_player_inputs` and is never written to the transcript (the record has empty prompt/schema/output; Safety's redaction log keeps the tuning evidence).
- Gotcha: Director.gd was 980/1000 lines, so the new private method had to be prose-tight (999 after) — future SYS work here needs a seam split first. The rejection test drives the UI through `InputBox.text_submitted` and must connect its observation lambda to `player_turn_sent` BEFORE the Director's, because the release is synchronous in instant-reveal mode.
- Gotcha: a rejected submission reuses the pending `GameState.turn` index (it does not advance), so a transcript can hold `turn: N` twice — `failed`/`unsafe_input` then `completed`.

## P1.32 — gate-r2 remediation: transcript redaction covers the event stream (2026-11-04, agent: commandcode)

- Split the record-level safety pass out of `Director.gd` into `game/llm/TranscriptRedactor.gd` (Director was at 999/1000 lines; it is 981 now). The Director only builds it once and hands `Callable(_redactor, "redact_record")` to `TranscriptLogger.set_redactor`.
- Gotcha that cost a debugging round: a `Callable` does NOT keep its RefCounted target alive. `Callable(TranscriptRedactor.new(_safety), "redact_record")` created a free-floating object that died immediately, so `redact_ready()` was false and every record was silently dropped (`log_turn` returned false with no error). The redactor must be held in a member var.
- Scan shape: `SaySafetyGate.scan_text()` → the filter's `filter_text` (stateless). Do NOT use the streaming `_safety.filter_text` for anything off-screen: it reads and writes `_history`/`_pending` and would glue two payloads into one match window, and it perturbs the display scan's state. One record == one reply, so its `say_chunk` fragments are joined and scanned as one utterance, then redistributed by character count (bars are length-preserving); a length-changing scan folds the reply onto the first fragment.
- Engine vocabulary stays verbatim (`VOCABULARY_FIELDS`: read/music/fx/action/feeling/cue/intensity/sprite/mood); unknown field names ARE scanned (fail-safe). `prompt` assistant messages are scanned (PromptBuilder keeps spoken text only), system/player messages are not.
- Gate B2 restore: `DateSceneTest.gd` is `b19dafd` + P1.21's `test_vram_usage_budget_under_800mb`. The gate asked for a byte-identical restore, but that blob predates P1.21's CODE-3 test that the same merge delivered — restoring byte-identically would delete approved coverage, so the union is kept and documented in the handoff.
- Suite is 358/358 (30 suites); the new `TranscriptRedactorTest` runs its cases against a scanner that implements only `filter_text`, so it also proves redaction never drives the streaming API.
