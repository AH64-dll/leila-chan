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
