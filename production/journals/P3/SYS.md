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

## P3.12 — shadow save + Reset Everything (round 2, 2026-11-04, agent: swe-2)

- S1 (CODE-1/DES-1/SAF-1) was one bug in three mirrors: `_recurse_wipe` trimmed the root with
  `trim_suffix("/")`, so the shipped `user_root = "user://"` became `user:/`, `DirAccess.open` returned
  null and the recursion returned silently — `Settings.reset_everything()` said `{ok: true, removed: 0}`
  while the shadow, slots, letters and diary lived on. Round 1's journal GOTCHA was half wrong: the trailing
  slash never reaches `remove_absolute` (only `path_join`ed children do), so the trim was unnecessary.
- `SaveSystem.wipe_root()` now drops exactly one separator per pass and never the scheme (`user://` stays,
  `user:///` → `user://`, not `user:`), and an unopenable directory goes into `errors` instead of a silent
  success. `DEFAULT_USER_ROOT` is a const so a test can pin the shipped value.
- Probed with the real autoloads on the shipped default, isolated via `XDG_DATA_HOME=<scratch>`: before
  `{ok:true, removed:0}` with `.leila/shadow.json` intact; after `{ok:true, removed:7}`, only
  `user://settings.cfg` left. That is the probe round 1's test hid by swapping in a scratch `user_root`.
- `ShadowSaveTest` (10 cases) pins `wipe_root` on `DEFAULT_USER_ROOT` and wipes the default root for real:
  probe in the real `user://.leila/`, every pre-existing file in `keep` so CI never erases real data.
- CODE-2: `_heal` re-applies both caps (newest `RUN_LIMIT` runs, first `shadow.limit` memories).
  DES-2 retargeted `wipe()`; DES-3 fixed the `memories` sentence (code + docs/07 §3.5); SAF-3 cites
  docs/05 M28 / docs/02 §8. DCR queued: docs/09 line 74 says OS-username "opt-out" — docs/02 §8/M28 say opt-in.
