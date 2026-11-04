# META journal — phase P3

## P3.13 — settings screen + Esc panic pause (round 1)
- One settings surface: `PauseMenu` autoload (Esc in `_input`, `PROCESS_MODE_ALWAYS`) with a pause
  page + settings page; Title's row calls `open_settings()`. Never build a second screen.
- `Settings.gd` is the only store — UI calls `set_*`, everything persists to `user://settings.cfg`;
  enum writes are validated and fail closed (Safety/Steering already read `content_level`; calmer
  mode IS `content_level = "calmer"`, not a second flag).
- Live pushes: FX (photosensitive), AudioDirector (per-bus volumes — only `bus_names()` exposed
  buses), typewriter `speed_scale` via ChatUI's `chat_ui` group + `set_text_speed_scale`.
- Gotchas: Esc belongs in `_input` (scenes' `_unhandled_*` can be swallowed by meta events);
  gdformat mangles `(x as Button).pressed.emit()` — use a helper; gdlint wants funcs after vars;
  `root.emit_signal("close_requested")` routes Quit through MetaDirector's M01 hold correctly.

## P3.13 — round 2 (SAF-1/DES-1, CODE-1, CODE-2, corrupt cfg)
- SAF-1: the calmer toggle may never grant `full`. `Settings` keeps `_pre_calmer_level` (persisted as
  `game/content_level_before_calmer`, only ever `full`) and off restores it; `""` when nothing was
  chosen. Rule of thumb: any "convenience" toggle over a safety field may only restore, never widen.
- CODE-1: `Settings.changed` is the sync bus; `PauseMenu` re-renders every row on any write with
  `set_pressed_no_signal`/`select`/`set_value_no_signal`, so two widgets over one field cannot disagree.
- CODE-2: capture `gui_get_focus_owner()` in `_open_if_needed()`, re-grab in `close()` only if the
  target is valid/in-tree/visible/focusable — the InputBox typing window survives Esc.
- SAF-4: treat `settings.cfg` as input: `_cfg_float/_cfg_bool/_cfg_enum` fail closed (NaN/inf/wrong
  type) and the setters refuse non-finite values. `clampf` does NOT stop NaN.
- Gotcha: gdlint caps a class at 20 public methods and `before_test`/`after_test` count — split a
  growing suite instead of adding a 19th and 20th test (hence `SettingsCorruptionTest`).
