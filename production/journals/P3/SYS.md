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
