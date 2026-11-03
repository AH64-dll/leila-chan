# META journal — P1

## P1.13 (2026-11-03) — UI kit: TextBox/InputBox/NameTag/ChatLog + typing indicator

- Built the kit under `game/scenes/ui/`; engines (`Typewriter`, `TypingIndicator`) are RefCounted
  so tests drive them with manual `advance(delta)` — deterministic, no frames needed.
- Convention: all UI strings/tunables in `game/data/ui.json` via `UiConfig.load_config()` over
  `DEFAULTS`; components take `configure(dict)` — keep new UI strings there from day one.
- Beat model: shared `{"i","text","closed"}` dicts between TextBox and Typewriter; a beat is
  drained only when its text is fully shown AND closed — stream pauses never read as "done".
- Chat log stores spoken text only on `beat_displayed` (aborts leave nothing); player lines on submit.
- Safety: `ChatUI.text_filter` Callable runs per say_chunk BEFORE display and log; P1.19 wires the
  real `Safety.scan` — flagged in the handoff as the required integration step.
- Gotchas: gdUnit4's StringAssert lacks `begins_with` (use `assert_bool(s.begins_with(...)).is_true()`);
  InputEvents don't propagate headless (drive `_unhandled_key_input`/`text_submitted.emit` directly);
  hand-minted `.gd.uid` strings must use Godot's charset — query `ResourceLoader.get_resource_uid`
  after import, else "invalid UID" warnings; `edit`-tool patches on gdformatted files need full rewrites.
- Next META task (P1.14): NewGame name rules — reuse `InputBox` + `ui.json` names.default_player.

## P1.13 Round 3 (2026-11-03) — Rework fixes (CODE-1, CODE-2, CODE-3, DES-1, DES-2)

- Capped `Typewriter._credit` at `1.0` during inter-chunk stalls (`_available() == 0`) to prevent burst reveals after network pause.
- In `TextBox.end_turn()`, hide indicator and fire `all_displayed` when zero say tokens arrived so turns close cleanly.
- In `InputBox._gui_input()`, handle `KEY_TAB` and emit `log_toggle_requested` with `accept_event()` so Tab toggles log even when LineEdit has focus.
- In `ChatLog.append_entry()`, call `remove_child` before `queue_free` on trimming oldest node so child count syncs with entries immediately.
- In `ChatUI.say_chunk()`, emit `push_warning` once per turn if `text_filter` is unset to warn about unwired safety filter.
