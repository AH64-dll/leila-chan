# ART journal — P2

## P2.15 — Stage FX (2026-11-04, round 1)
- Built the stage-3/4 vocabulary (shake_big, flicker, darken, vignette_red, glitch, text_bleed) + the stage
  baseline desaturation. FX.gd resolves `casting.stage_fx` (generated) per stage; Director re-syncs it on
  `GameState.stage_changed`; the Character host ramps it so a transition reads as a drain.
- **Convention: one screen pass.** Godot 4 copies the 2D screen texture once per frame, so two full-screen
  sampling shaders cannot compose — the later one re-samples the pre-effect screen and erases the earlier.
  Keep every stage effect as a uniform on `game/shaders/stage_fx.gdshader` (`Character/OverlayFX/StageFX`,
  CanvasLayer 3, hidden at rest). `FXStageHostTest::test_exactly_one_screen_sampling_pass_exists` guards it.
- **Convention: photosensitive safety is structural, not cosmetic.** The flicker's dim pattern's steps are
  clamped to `FX_FLASH_MIN_STEP_S` at runtime, `vignette_pulse_hz` is pinned by the host (shader hint ≤ 2 Hz),
  and `invert_flash` reports `photosensitive` instead of firing. Tests check both the pattern and the sampled
  frames (≤ 2 direction changes/s in photosensitive mode, > 5 edges/s in normal mode).
- Gotcha: `ShaderMaterial.get_shader_parameter()` returns null for a parameter that was never set — never read
  a uniform back as state; the host tracks the values in fields (`Character._flicker` etc.).
- Gotcha: headless gdUnit runs uncapped, so `_wait_seconds` must sum `get_process_delta_time()` (never count
  frames), and flicker sampling must take the *minimum* over a window — the lit steps are part of the cue.
- Dev tools: `game/tools/fx_shot.gd` (peak captures + uniform state line) and `fx_bench.gd` (frame-time
  percentiles; llvmpipe 251 fps, Radeon 760M 3354 fps with all six live). Both need a display, not `--headless`.

## P2.15 — Stage FX (2026-11-04, round 2)
- **Convention: a safety accommodation needs a door, not just a flag.** `Settings` now owns
  `set_photosensitive()` / `toggle_photosensitive()` (push to `/root/FX` first, then persist to
  `user://settings.cfg`, which docs/07 §3.5 keeps across "Reset Everything") and the Title menu has the
  keyboard-reachable row that writes it. Any future accessibility flag should follow this shape: store →
  live push → one surface a player reaches before the hazard.
- **Convention: pass visibility is cue liveness, not uniform values.** `Character._live_fx` + `_end_fx(name)`;
  each cue's own final tween callback releases it. Value-sniffing hid a flicker at its lit step (CODE-1), and
  "all uniforms at rest" is simply not the same predicate as "no cue running".
- `Date.stage` is `-1` ("follow GameState") by default — an export that a scene transition can't set must
  never assert stage 0 over a mid-campaign GameState (DES-3). Dev tools still pin a value.
- `clear_screen_fx()` now resets `_cam.offset` and the live set; a killed tween leaves its last frame on screen.
- Filed a DCR for docs/05 §0.4 ("disables flicker") vs docs/02 §2.3 / docs/10 §2.2 ("dim"): the dim ships,
  because it is compliant and doc-majority, but docs/05 §0 is a hard rule — the producer/user decides.
- Gotcha: a dev tool run with `--script` (bare `SceneTree`) has **no autoloads** — `Title.gd` fails to compile
  with "Identifier not found: Settings". Capture UI that touches an autoload from a real scene run (Boot.tscn
  + `import -window root`), not from `ui_shot.gd`-style `--script` tools.
- Gotcha: after merging `main` (or any branch that adds `class_name` files), run
  `./tools/godot.sh --headless --path game --import` before a direct gdUnit call, or discovery dies with
  "Identifier `CorruptionSession` not declared".

