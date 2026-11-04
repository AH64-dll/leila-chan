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
