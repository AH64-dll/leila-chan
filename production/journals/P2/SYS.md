# SYS journal — P2

## P2.23 F1 controller wiring — ChatUI registration (round 1, 2026-11-04, agent: commandcode)

- Built: `Date._ready()` now calls `Director.register_chat_ui(chat_ui)` with the rest of its ChatUI wiring
  (`game/scenes/Date.gd:95`), and `Date._exit_tree()` clears it (`:117-125`, identity-guarded so a second
  live date's ChatUI is never unregistered). This makes P1.31's unsafe-input release reachable in the
  shipped scene; the `has_method` guards in Director have a real caller now.
- Convention chosen: the node that instantiates a UI owns its autoload registration, register in `_ready`,
  clear in `_exit_tree`. An autoload-side group lookup would be a second wiring path for one line.
- Test convention: the P1.31 rejection tests no longer register a bare `ChatUI.tscn`; `_new_chat_ui()`
  instantiates `Date.tscn` and returns `date.chat_ui`, so the tests die if the scene wiring is removed.
  Prove it with a mutation (`register_chat_ui` -> `pass`): `DateSceneTest.gd:64` and
  `DirectorFallbackTest.gd:307-308` go red, then the input-lock assertions at `:338-340`.
- Gotcha: `Director.reset()` does NOT clear `chat_ui_node` (deliberate — a restart-date without a scene
  reload must keep the UI). Tests that instantiate a bare ChatUI must still clear it themselves; the Date
  scene now does it via `_exit_tree`, so DateSceneTest/SceneFlowTest need no teardown line.
- Gotcha: never edit `game/` while `tools/test.sh` is running — the first full run here was green but mixed
  code (an edit landed mid-run), so it had to be re-run. gdUnit compiles suites progressively.
- Gotcha: `DirectorTest.test_step_0_input_safety_rejection` rejects with NO UI registered, so adding a
  `push_warning` to the no-UI branch would be a new warning on an intended path; the red-test route is used
  instead. `Director.gd` is 983/1000 gdlint lines — 17 lines of headroom left.
- Next SYS on this seam: the submit half is still missing — nothing in `game/` calls
  `Director.submit_player_input`, and `Date._on_player_turn_sent` only counts. Wire
  `ChatUI.player_turn_sent` -> `submit_player_input` there and move the counter onto `turn_completed`.
