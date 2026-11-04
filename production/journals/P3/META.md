# META journal — P3

## P3.14 — New Game name rules complete (round 1, 2026-11-04, agent: deepseek)
- Built `game/data/name_rules.json` + `Corruption.NAME_RULES_PATH`/`DOCS_NAME_RULES`: every tunable
  number (decay/kun/tag-swap/shadow gates and chances) is data, the consts are the fallback, and the
  merge is section-wise so a partial file still degrades to documented values. Convention worth
  keeping: pure, seeded rule functions live in `Corruption`; `CorruptionSession` only decides *when*
  they run (step 7, after `wrong_name`, which owns the word-kind slot for name words). Stage reading:
  "the name decays with her" is progressive — decay gate 3 stays live at 4–5, `-kun` joins at 4, the
  log tag swap at 5 — and each rule draws exactly one `randf` per player-name word while it has
  capacity, so a beat rewrite and a live stream stay byte-identical.
- GOTCHA: name caps are `max_per_turn`, so `_name_counts` resets in `begin_turn`/`abort` ONLY. Leaving
  the reset in `_reset_beat` (as the first draft did) makes multi-beat turns re-roll. Related: an
  `elif` between decay and `-kun` starved `-kun` forever (decay is only bumped when it *fires*, so its
  capacity never ran out). Roll both, let decay own the text, bump only the rule that landed.
- GOTCHA: a stage-4 zalgo burst decorates the name word *before* the name rules, so any test that
  compares the name's exact text must run at stage 3 (where zalgo is gated out). `wrong_name`'s
  stranger list contains "Ren", a prefix of "Renji" — compare exactly, never with `begins_with`.
- GOTCHA: gdUnit4 v6 has no `fail_test()` — use `fail(msg)`. JSON numbers parse as `float`, so a
  data-vs-docs table test needs `is_equal_approx`, and `assert_object()` on a String is invalid.
- The shadow line ("That's not what you were called last time.") compares the typed name against the
  shadow's `first_name` AND its `names` list: a name she has already known is not news. Otherwise a
  player who renamed once would hear it on every later run, which is plainly false. Read both from a
  single `SaveSystem.shadow_data()` call *before* `begin_new_game()`, which appends the new name.
- GOTCHA: `SaveSystem` sits exactly at gdlint's `max-public-methods` (20) — adding a `shadow_names()`
  helper fails `gdlint game/` with "Class global scope has more than 20 public methods". Read
  `shadow_data().get("names")` instead of growing that surface.
- Privacy: `Settings.os_username()` is the only environment read and returns `""` until the player
  opts in; only the flag is persisted. P3.13 must add the menu toggle (`set_use_os_username` is the
  seam). `PlayerNameRules.MSG_*` still duplicate `data/ui.json` — P5.15 externalises all six.
- Wave hazard seen this round: an interrupted agent had deleted `Corruption.gd`'s whole public API
  mid-reapply. Before continuing someone else's half-done edit, diff `func` names against `HEAD`
  (`git show HEAD:<file> | grep "^static func"` vs the working copy) instead of trusting `git status`.

Round 2 (rework) of P3.14:
- The `-kun` sign is docs/02 §1.1's, not the negated one: a POSITIVE stress suggestion is the angry
  turn. `stress > angry_stress` appends on calm turns (118/200 at affection 100) and never on angry
  ones. When a mood drives a text rule, read the meter-scaling line in docs/02 §1.1 and write the
  sign into the docstring + a 200-seed test, because the fixtures are the only thing that can pin it.
- GOTCHA: gdlint's max-public-methods counts `before_test`/`after_test`, so a GdUnit suite caps at 18
  tests, not 20. Splitting a suite with python: blocks end at the next top-level `func`/`##`, and any
  `for`-local `var` must not be reused after the loop (GDScript block scoping) — that broke a split
  with `Identifier "out" not declared`.
- GOTCHA: `SaveSystem` is at gdlint's 20 public methods, so persistence helpers go on `ShadowStore`
  (`has_run(day, turn, stage)` is now the single "is this a real ended run" definition used by both
  the seal and the New Game gate).
- Cross-process data must be stored, never inferred: the shadow line read the live `GameState.stage`,
  which is 0 after a relaunch, so `ShadowStore.last_stage` was added (blank/seal/_heal) and the gate
  is `live if a run is in progress else stored`. Prove such things in two processes, not one.
- Content the writer tunes belongs in `data/ui.json` with the code consts behind it as a fallback —
  `PlayerNameRules._messages()` now merges the file over the six `MSG_*` consts, the same shape as
  `Corruption.DOCS_NAME_RULES` behind `name_rules.json`.


## P3.10 — meta events M21–M26 (round 1, 2026-11-04, resumed from checkpoint d8674a4)

- Ship shape: `MetaEventsM21.gd` (Node) mounts under MetaDirector via `EFFECTS_PATHS`; scripted S events
  (M23/M24/M26) go through `poll_scripted(stage)` so the DIRECTOR charges the scene budget, the quiet
  turn and `meta_seen` — the module only decides *whether* an event is due (stage → doc paths → seeded
  `chance` roll → `_can_apply`). Offered O events (M22 mimic_player, M25 hide_ui) stay catalogue rows
  in `meta_events.json` and land through `_fire` → `module.fire()`, queued until `turn_displayed`.
- Scripted content lives in `data/meta_events_m21.json`, NOT `meta_events.json` — that file is the
  OFFERED-actions catalogue only (`_doc` says so, `test_meta_events.py` pins the vocabulary). Sibling
  convention: P3.09 → `meta_messages.json`, P3.11 → `meta_notes.json`.
- Convention worth keeping: the F3 demo seam is GENERIC — DebugOverlay iterates `MetaDirector`
  children, reads `debug_ids()`, dispatches `debug_fire(id)`; modules publish `state()["last_demo"]`
  for the read-back line. A new event wave adds zero overlay code.
- M23/M24 never lose the truth: `MetaLogEdits` (static RefCounted ledger, `user://.leila/`) is a
  display override keyed by (speaker_key, text, occurrence) — ChatLog stores the player's real words
  and renders `MetaLogEdits.shown()`, so "Restore my words" in Extras is a ledger clear + `rerender()`.
  Occurrence keys keep two identical lines distinguishable without ids in the save format.
- M22's input safety is three layers: `show_foreign_draft` writes silently (no draft telemetry — her
  words are never the player's deleted draft), `draft_changed` = the player touched the box → stop,
  and `_advance_mimic` re-checks `text == prefix` before every write so a missed signal can't fight a
  deletion. M25 hides modulate/visibility only; Esc never reaches `_unhandled_input` (PauseMenu owns
  `_input`), and a new/aborted turn always calls `_restore_ui`.
- M26 is a display lie (`PauseMenu._sabotage` offset on `set_value_no_signal`), never a write:
  Settings/AudioServer untouched, touching the slider or `clear_sabotage()` snaps back. Gate needs
  `meta_settings_seen` — the lie only lands on someone who has a slider to remember.
- GOTCHA: `state_reset`/`reset_session` must clear EVERY per-session var incl. `_last_demo`, or a test
  that resets then reads `state()` sees the last run's demo. gdformat collapses stray double blanks —
  run it before committing, not after the handoff text is written.

## P3.10 — round 2: every r1 finding answered (2026-11-05, agent: gemini-3.8-flash)
- CODE-1/DES-1 fix: `MetaEventsM21._due_scripted()` looped `SCRIPTED_ORDER = ["M23", "M24", "M26"]`
  and returned on the first RNG roll without checking if the event had already been spent in the
  save. Because M23 is once-per-save and has a 35% chance at Stage 4 on SPLIT, proposing spent M23
  which `MetaDirector._fire_scripted` subsequently rejected meant M24 and M26 were starved on 35% of
  turns. Adding `if not _allowed_here(id, stage): continue` skips spent/capped events and checks the
  remaining candidates.
- CODE-2/SAF-1 fix: `MetaLogEdits.gd` now has `static var _clock: Callable = Callable()`, public
  seam `set_clock(Callable)`, and `_now() -> int` helper. `record()` writes `"at": _now()`,
  restoring determinism and injectable time across test suites.
- CODE-3/DES-2/SAF-2 fix: `MetaLogEdits.clear()` unlinks `_path` (`user://.leila/log_edits.json`) and
  wipes static `_rows`. Wired into `GameState.reset()` and `SaveSystem.begin_new_game(name)` (as well
  as `SaveSystem.wipe_everything()`), guaranteeing that stage-4 chat log rewrites cannot leak into
  Stage 0 Day 1 of a new campaign.
- CODE-4/DES-3/SAF-3 fix: authored formal Round 2 handoff (`production/handoffs/P3.10.md`), updated
  role journal, verified test suite (1034 gdUnit4 tests + 559 pytest checks all passing).

# META journal — phase P3

## P3.08 — MetaDirector scheduler (2026-11-04, round 1)

- Built the docs/05 §3 offer scheduler on P2.10's M01 seam: `data/meta_events.json` (rules +
  catalogue), per-turn weighted roll `hash(seed_base:turn)` (Campaign's convention), offers ride
  exactly one turn, M01 evicts the oldest scheduled offer but the enum never exceeds 2.
- Conventions: OPPORTUNITY lines stay in `stage_gates.gates.opportunities` (TurnSchema owns the
  read); every catalogue row needs a `note_line` (docs/05 §2 "she is told afterwards") or it is
  never scheduled; `once_per_save` rides `GameState.flags["meta_seen"]` (persists through saves,
  clears on New Game/reset — that flag is also the Extras "what happened" list docs/05 §3 promises);
  scene cap counts **open offers + fired events**, so the player can never take the (cap+1)th event.
- `Settings.immersion` ("standard"/"deep") now exists for docs/05 §0 rule 4 — missing/odd values
  fail closed to Standard. P3.13 owns the UI row; wire it to this var.
- Gotchas: M01 tests park the scheduler via `MetaDirector.set_catalog({"rules":
  {"scheduler_stage_min": 99}})` — otherwise `offers(3)` legitimately returns a second action and
  the old `is_equal(["refuse_exit"])` assertions flake on the lottery. `execute_after_text` is the
  single place events are charged: `_fire()` bumps scene/session/cooldown/"never two in a row"
  together, and M01 counts too.
- Careful: the brief's edit ran from the main tree's CWD once — always edit with the absolute
  worktree path; a stray `stage_gates.json` edit in `/run/media/.../lila` was reverted, not committed.
- Next (P3.09): `execute_after_text` currently only *counts* non-M01 actions — the M02/M09/M12…
  effects hook in there (or on `event_fired`); `end_date` is intentionally NOT in the scheduler
  (docs/02 story action, no meta row).

### P3.08 resumed (same round 1, after the interruption)

- Fixed the interrupted edit (`DebugOverlay` had lost `_last_turn_data`'s declaration) and learned that
  `# gdlint: disable=<check> — reason` is inert: gdlint swallows everything before the first comma.
- docs/05 §0 is a per-row contract: `_hard_rule_violation()` → "R1…R5…" (writes only under `user://`,
  no network/real-crash/personal-file flags, OS tricks only under Immersion: Deep, `fallback` per row);
  `eligible()` refuses such a row, `state()["hard_rule_violations"]` shows it in F3.
- Data: every row carries `fallback`, `write_note` declares `writes: "user://letters/"`; both pinned by
  `tests/test_meta_events.py`. §0 cases live in `MetaHardRulesTest.gd` — the scheduler (16) and overlay
  (18) suites are both at the 20-public-method lint cap.
- Gotcha for P3.09: `debug_offer` bypasses gates *and* caps on purpose (F3 manual test); only the roller
  path enforces stage/§0/caps.

## P3.08 — round 2: every r1 finding answered (2026-11-04)

- The OPPORTUNITY line is no longer a queue side effect: `_open_offer` only records the sentence, and
  `MetaDirector.turn_events(events, stage)` feeds it into `Director.build_turn_context()` — the same submit
  that carries the enum. `_close_offer` no longer erases from `GameState.pending_events`; nothing is queued.
- Meta caps are stamped with **the turn the player answered**: `execute_after_text(action, answered_turn)`,
  Director passes `_turn_index` (read before `apply_turn_meters()` advances the counter), so
  `turn - _last_event_turn <= 1` silences exactly one turn. Cooldowns share the same basis.
- Scene budget now has three seams: per pick in the roll, before the close is held (a spent scene is not
  intercepted — the press closes), and at execution (an outlived offer is consumed without firing).
- One meta floor: `scheduler_stage_min()` = the lowest row gate; `rules.scheduler_stage_min` and
  `gates.meta_min_stage` are deleted, so M31's documented St 2 is reachable.
- §0 is structural: `ACTION_CLASS` (code) decides rule 4 — deleting `immersion_deep` cannot exempt a row —
  and `ROW_KEYS` closes the row vocabulary, so unknown effect keys (`cursor_warp`, `reads`) are `R0`, a
  write-class action must declare `writes`, and `fallback` must be a non-empty string.
- Tests: `MetaOfferPromptTest.gd` drives three real `Director.submit_player_input` turns (the r1 coverage
  gap); scene-budget cases moved to `MetaSceneBudgetTest.gd` because the scheduler suite was at the
  20-public-method cap. Read `_current_prompt`/`_current_schema` BEFORE awaiting the turn.
- Gotcha: `Director.gd` sits exactly at gdlint's 1000-line cap — every line added there needs one removed;
  `MetaDirector` is at exactly 20 public methods (`load_catalog_doc` was folded into `set_catalog`).
