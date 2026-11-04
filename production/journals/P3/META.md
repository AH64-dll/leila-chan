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
