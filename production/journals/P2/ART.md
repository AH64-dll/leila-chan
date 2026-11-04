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

## P2.15 — Stage FX (2026-11-04, round 3)
- **Convention: a test that samples a random effect must seed it *and* take a maximum over a window.** The
  round-2 `clear_screen_fx` test sampled one instant of `_fx_shake`'s unseeded 25 Hz offsets and could land on
  a zero crossing (the reviewer's full run failed at 0.464 < 0.5). `seed(SHAKE_SEED)` right before `play_fx`
  replays the 30 offsets, and max-over-0.2 s is the pattern the sibling `shake_big` test already used; 20/20
  isolated runs green, 15/15 cases each.
- **Convention: a test cleanup that calls a *saving* setter must run before restoring the seam path.**
  `Settings.set_photosensitive()` writes to `settings_path`, so restoring `Settings.PATH` first made the suite
  overwrite the player's real `user://settings.cfg` with `photosensitive=false` — the suite silently disabled
  the accommodation it exists to protect. Proof of the fix: md5+mtime of the real file (left holding
  `photosensitive=true`) unchanged across the settings suites and the full 551-case run.
- Gotcha: after merging `main` (P2.09/.11/.14) `Director.gd` was 1004 lines and `tools/test.sh` went red on
  gdlint's 1000-line cap alone while all 551 tests passed. Both sides had compacted to fit; the union did not.
  Comment compaction is the repo's accepted fix (P2.14 did the same), but the file now has zero headroom.

## P2.14 — SpriteResolver T2–T3, YANDERE/AWAKE paths, intensity-driven motion (2026-11-04, agent: commandcode)
- Built the T2–T3 resolver: each sprite's documented tier (docs/03 §1) now lives in `casting.sprites[id].tiers` and only its **minimum** gates a path candidate; a gated override falls through to the feeling's base cell, never to the fallback face. YANDERE angry at stage 3 is 17 (the knife waits for T3); AWAKE cold/confused at stage 3 are 07/08.
- The reveal budget is **scene state** in `resolve_beat` (`_reveals` + `reset_scene()`), not in the pure `resolve()` — that keeps the 594-cell table test meaningful. `1 reveal per scene` (21) gates the sprite; `terminal climax only` (30) withholds the `system` sting below stage 5 and lets `fx_below_stage5` degrade the visual.
- Conventions: every new rule is generated data — `motion_intensity` (i1 ×0.6 / i2 ×1.0 / i3 ×1.4), `siblings_corrupt` (21→24→28, 22→26↔28, 23↔29, 25→29, 27→24, 30→21) and `paths.AWAKE.shader` — with validation in `build_casting.py`, a generated docs/10 section, and a test. On-enter events fire through `game/scenes/SpriteEnterEvents.gd`; `Director.last_sprite_enter` keeps the events+report for tooling.
- Gotcha: `AudioDirector` cue playback is **asynchronous** (threaded stream load), so a test that counts `cue_played` must await frames; reading the count immediately returns 0 and looks like a dispatch bug. Denials (`no_files`, `gated`) and engine-cue dispatch are synchronous; engine cues bypass stage gates and the silence rule but not asset existence.
- Gotcha: gdlint caps are hard. `Director.gd` already sits at 1000 lines / 20 public methods, so new Director-side logic must live in a helper class (that is why `SpriteEnterEvents` exists); a test suite is capped at 20 public methods (fold motion evidence into the existing preset test, split new coverage into its own suite).
- Gotcha: `--script res://tool.gd` runs **without the project's autoloads**, so a tool that instantiates Character (it compiles against `FX`) must run as a scene: `godot --path game res://tools/MotionShot.tscn -- <args>`. Capture needs a display (xvfb-run works) and `Engine.time_scale` slows a tween enough to sample.
- Next: P2.15 consumes `packet.shader` and implements the stage fx that entry events already dispatch (`vignette_red`, `darken`, `glitch`, `her_eyes`); P3.06 owns SPLIT/TSUN/HOLLOW/ANCHOR rules; dissonance + mask slip now have an owner (SYS + ART/SAFE, proposed P2.27 — see round 2).

## P2.14 round 2 — CODE-1/DES-1 fix + mutation-proof tests (2026-11-04, agent: commandcode)
- Lesson: a scene-scoped budget checked in `resolve_beat` is **not** enforced for any later step of the same beat. The anti-repeat swap runs after the cap check, so `_sibling_for()` must re-read `_reveal_cap()`/`_reveals` itself. `30 → 21` was reachable twice per scene; the sweep harness (2 772 sequences, 18 beats each) is the cheap way to prove a whole-path invariant — 144 overruns before, 0 after.
- Lesson: "kept across `set_reduced_motion`" lives in the re-run call (`_apply_motion(_motion, _motion_scale)`); a test that enables reduced motion *before* the beat never touches that line. Assert at i1 and i3 with reduced motion switched on **after** the beat, otherwise the i2 default makes the mutation invisible.
- Lesson: for a single-resolution seam, count `SpriteResolver.beat_resolved` emissions around the entry point instead of asserting the resulting sprite — two resolver passes resolve the same cell.
- Discipline: run every new assertion against a deliberate mutation (revert the fix in place, run the suite, restore from a `/tmp` copy). All three round-2 assertions fail without their code, which is the evidence a reviewer wants.
- Gotcha: merging `main` grows `Director.gd` (it was 992 before our 13 lines), so the gdlint cap bites. Keep the P2.14 additions at ~6 lines (inline `preload(...).new()`, no separate `const`, folded comments) so the file lands on exactly 1000.

