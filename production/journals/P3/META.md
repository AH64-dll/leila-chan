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
