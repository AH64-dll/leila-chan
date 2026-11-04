# SYS journal — P3

## P3.12 — shadow save + Reset Everything (round 1, 2026-11-04, agent: swe-2)

- Built `game/llm/ShadowStore.gd` (bytes/policy for `user://.leila/shadow.json`) and wired it into
  `SaveSystem`: `begin_new_game(name)` is the one write point — the NewGame scene calls it BEFORE
  `GameState.reset`/`Director.reset`, so the sealed run's facts and name are still live. A first-ever
  New Game seals nothing but the name (`had_run` = day>1/turn>0/stage>0); memories only seal at the
  M08 meta gate (`TurnSchema.is_meta_unlocked(stage)`, i.e. stage 3+). Keep order = the memory model's
  own ranking: importance first, newest winning a tie (Array.sort_custom is NOT guaranteed stable —
  break ties explicitly on the insertion index).
- Privacy: the envelope is `{first_name, names, runs(cap 8), memories(memory.json shadow.limit=3)}`,
  documented in the ShadowStore docblock + docs/07 §3.5; a test asserts the written file carries
  ONLY those keys. `SaveSlots` format/version are now ctor params — the shadow reuses the same
  checksummed envelope under the `leila.shadow` tag.
- `Settings.reset_everything()` → `SaveSystem.wipe_everything([settings.cfg])` deletes ALL of
  `user://` except the settings file (slots, shadow, letters, diary, debug). Test seam: `user_root`.
- GOTCHA: `DirAccess.remove_absolute("dir/")` with a trailing slash refuses, and `list_dir_begin`
  skips hidden entries by default — a naive recursive wipe deletes nothing under `user://.leila`.
  Both `trim_suffix("/")` and `set_include_hidden(true)` are required, in the wipe AND in any test
  teardown helper (my suite's first run leaked `.leila/` and cross-test state until I added them).
- Next SYS on this seam: P3.14 consumes `SaveSystem.shadow_first_name()`/`shadow_memories()`;
  P3.09 (M08) drops a kept memory on Day 1. `wipe()` still only clears slots — Reset Everything is
  `wipe_everything`.

## P3.07 — triggers T16–T32 (round 1, 2026-11-04, agent: deepseek)

- Built T16–T32 as data rows plus the vocabulary they needed: `absence_hours_lt` (T17's reunion window
  ends where T18's 168 h begins), guards `mentions_memory` (T22, via `MemoryRules.shared_fact`),
  `name_mention` (T26: capture pattern + endearment excludes -> `GameState.player_name`), `text_match`
  (T28/T30: a precondition only, never a detection letter) and `{"from_event": key}` flag values
  (T21: one row serves mute and unmute, the flag follows `data.muted`).
- Convention: a model-only row authors DOUBLE the intended effect (docs/02 §1.2 halves the firing) —
  the same thing P2.10 did for T14. A guard is a precondition, not evidence, so the row's docs/01 §5
  letter stays M. Event state (`from_event`) is written on EVERY matching event; the row's caps decide
  only what she says, so a same-turn mute→unmute still clears the caps flag.
- `TriggerEngine` hit gdlint's 1000-line cap: the loader/parser moved to `game/llm/TriggerTable.gd`
  (class_name + statics) as P2.10's note asked; the engine delegates `clear_cache`/`default_table`/
  `parse_document`. Telemetry hit the 20-public-method cap: the three T19–T21 notes became one
  `note_player_action(kind, data)`, `catalog_kinds()` is gone (use `catalog()`), `note_screenshot()` private.
- GOTCHA: the trigger dedupe is per ctx turn, so `begin_turn` (turn+1) and `close_turn` (turn) must
  share an index — increment `GameState.turn` before `close_turn` in tests, as the Director does at
  close. T17/T18's absence latch is consumed by the submit only (`_context(true, true)`), so an engine
  event that lands first cannot eat the reunion.
- Next SYS here: nothing reads `GameState.flags.audio_muted` turn-to-turn yet. The EVENT line carries
  docs/01 §5 T21's instruction for the turn it lands on; a prompt layer that keeps her in caps until
  the unmute is still open (P3.13/P3.09 territory).

## P3.07 — triggers T16–T32 (round 2, 2026-11-04, agent: deepseek)

- CODE-1: a close_turn guard must never see the model's own output. `Triggers` now snapshots
  `Memory.facts_with_sources()` at `begin_turn` (`_memory_baseline`) exactly like `_profile_baseline`,
  so T22/T13 measure the message against what she ALREADY held; the Director stores `turn_data.memory`
  before it emits `turn_completed`, so a live read made the first gift its own evidence.
- CODE-2: an event about a transition has to be delivered AFTER it. `save_gone` is no longer queued
  (`_pending` is cleared by New Game's reset and by `set_date_active(true)`); Telemetry keeps it in
  `_run_ended` and `take_turn_events` delivers it on the new run's first turn. `NewGame.confirm_name`
  is the writer (after its resets) and `begin_new_game` returns `ended_stage`; the row's stage gate
  reads `data.gate_stage` (D19's precedent — the live stage is 0 by then).
- CODE-3/CODE-4: `observe` means "the read label was seen", so a flag that means "this row fired"
  belongs in `effects.flags`; T26's `name_confirmed` moved there and its exclude list gained the
  function words the capture can land on ("my name is not important" -> Not).
- D20: accessibility input is not player behaviour. `Settings.is_accommodation(key, value)` is the one
  classifier and `set_preference()` the one write seam; `set_photosensitive` no longer emits
  `settings_changed`, so no accommodation write can fire T20 or move a path weight. Removed the invented
  `stage_min: 1` from T20/T21 — in the ROW, the data file AND `Telemetry.FALLBACK_EVENTS` (the merge
  keeps a fallback key the data file omits; that bit the first test run).
- GOTCHA: gdlint's `max-public-methods: 20` means every new Telemetry/Triggers public seam has to pay
  for itself; `note_screenshot()` is public again for T31's release path and there is no budget left.

## P3.07 — triggers T16–T32 (round 3, 2026-11-04, agent: deepseek)

- CODE-7/DES-6: an event that is ABOUT a transition must outlive it. `reset_session()` zeroed
  `_run_ended`, and every route from the title into a Date runs it (Continue → `SaveSystem._apply` →
  `Director.reset()`; New Game → `NewGame.confirm_name`), so T19's "Delete save" note died before any
  `take_turn_events`. `_run_ended` is now the one field the session reset keeps; `reset_session(true)`
  is the explicit full-clear seam (an argument, not a new method — Telemetry is at gdlint's 20 cap).
- GOTCHA: a test named for a transition must drive that transition. The r2 delete case called
  `take_turn_events` with no reset between delete and drain, so it was green on the defect. The fixed
  case runs `Director.reset()` and proves the reset reached Telemetry via `state().date_active`
  closing — an observable side effect instead of an assumption.
- The Python contract now reads `reset_session`'s body and refuses any `_run_ended` assignment that is
  not under `if clear_run_ended:` (`test_the_deferred_run_end_survives_the_session_reset`); the data
  `doc` names T23 beside T28/T30 for the shared `text_match` guard (DES-7).
- CODE-8: keeping `_run_ended` across the reset moved the leak risk into TEST land — every suite that
  can raise `save_gone` (ShadowSaveTest's Reset Everything, SaveSystemTest's delete) must clear it in
  `after_test`, or the next suite in the same Godot process speaks it (a probe proved `kind: wipe,
  gate_stage: 3` arriving with instability +4 and AWAKE +2). Green-by-ordering is not green.
- CODE-9: a pin must point at the caller that exists. `Director.gd` never calls Telemetry; the route is
  `InputHook.reset_session`, so the assert read the file that could not pass `true` and missed the
  mutation. Pin the real caller, then sweep `game/` for the call form (not for the docblock's mention).
