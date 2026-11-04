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
