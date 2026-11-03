# ART journal — P1

## P1.10 — Character scene + SpriteResolver T0–T1 (2026-11-02)
- Built `SpriteResolver` (autoload) and `Character.tscn/gd`: tier map read from `casting.tiers`, base table, min-tier/flag gates, sibling anti-repeat, fallback; 140 ms A/B crossfade; nine motion presets; four camera presets.
- `casting.json` stays the only table: added the `siblings` map to `build_casting.py` with validation and generated docs/10 §3.1; bridge re-run is 0-diff (66 files, manifest `a7602bcf8b0331f6`).
- Conventions: sprite id → `res://assets/sprites/leila/<basename>`; x2 art at scale 0.5 = 1:1 texels in the 384×688 viewport; `texture_filter=1` pinned on the Character root; camera presets min-fit their rect and clamp inside the frame.
- Gotcha: gdUnit4/GDScript lambdas capture scalars by value — async probes must write through a Dictionary or the assertion is vacuous (the first motion-test draft passed nothing).
- Gotcha: the bust camera reads the *current* sprite's `bust_crop_native`, and pivots must be recomputed on every swap before motion/camera; lean-in and face depend on `eyes_native`.
- Next: P1.11 connect `twitch_fired` → chromatic split and the glitch shader; P1.16 instantiate the scene, call `set_feeling` before `say`, bind `Settings.reduced_motion`; P2.14 owns path rules, dissonance and T2+ siblings.

## P1.10 — Round 2: pixel-perfect camera + reduced-motion snap (2026-11-03)
- Camera presets now settle on integer native-pixel zooms 1/2/3/4 with the origin snapped to the 1/zoom grid; do not reintroduce the old fractional min-fit. Anchors: knees `(192,196)`, bust = authored `bust_crop_native` centre `(192,120)`, face = `eyes_native` midpoint + 24 px (`(184,122)` / `(184,118)`).
- `_cam_live` records the live target including an i3 push; `set_reduced_motion(true)` calls `_camera_to(_cam_live, true)`, killing the tween and snapping. `lean_in` under reduced motion is a static 1.15 pose, no tween.
- Gotcha: `get_canvas_transform()` and `Camera2D.is_current()` are stale within the frame — await one `process_frame` after `set_camera()`. `get_screen_transform()` is the composed local→screen transform; don’t compose `get_viewport_transform()` on top of it (double camera).
- Gotcha: at zoom 3 the native pixel grid lands at screen y ≡ 2 (mod 3) for the bust anchor, so a still block-uniformity check must use the camera grid offset (`344 - cam.y*zoom mod zoom`), not multiples of 3.
- Breathing is deliberately sub-pixel; freeze (`empty` i1/i3) for exact composed-transform tests and freeze the body for still measurements. Never remove breathing to make a settled-camera test pass.
- Next: P1.11 FX; the design reviewer should confirm the 1/2/3/4 ladder and the tight 4× face crop (see handoff deviation).

## P1.11 — FX v1: blush_glow, hearts, sparkle, shake_small, zoom_face (2026-11-03)
- Built `FX.gd` (autoload) and `Character.gd` screen-effects host: stage gates + 3-turn cooldowns read from `casting.fx`, rate caps for `shake_big`/`glitch` (max 1 per 2 turns), and debug F6 panel (`FxMenu.gd`/`FxMenu.tscn`).
- Authored five Stage 0 effects on Character: `blush_glow` (CanvasLayer pulse), `hearts` (pixel-art rising particles in palette), `sparkle` (twinkle particles), `shake_small` (camera offset 200 ms with reduced-motion cut), `zoom_face` (temporary camera push toward bust with auto-return); connected `twitch_fired` → chromatic split (`glitch_split.gdshader`).
- Conventions: `casting.json` is the sole source of FX gates, cooldowns and caps; `FX.gd` decides whether an effect runs, `Character.gd` decides how it renders; particle textures conform to `palette.json`.
- Gotcha: In GDScript typed for-loops (`for fake: Node in _fakes:`), if an instance was freed earlier, GDScript raises an error upon assignment before `is_instance_valid` can be evaluated; keep iteration variables untyped when dealing with potentially freed nodes.
- Gotcha: `queue_free()` retains nodes in parent child lists until frame end; call `remove_child(child)` before `queue_free()` in `_cut_fx_motion()` so child counts drop synchronously on reduced-motion cuts.
- Next: P1.16 Date scene integration and UI binding; P2.15 stage shaders for later stage effects (`rain`, `shake_big`, `flicker`, etc.).
## P1.16 — Date scene assembly + café background art (2026-11-03)
- Built `Date.tscn` and `Date.gd`: composite assembly wiring `Background` (`res://assets/bg/cafe.png`), `Character.tscn`, `DateFX.gd` overlay, and `ChatUI.tscn` (holding `TextBox`, `InputBox`, `ChatLog`).
- Generated `game/assets/bg/cafe.png` via deterministic generator `tools/art/generate_cafe_bg.py`: native 384×688 pixel art depicting the cozy corner café table, window, counter, and menus in exact palette colors (28 colors used, 0 off-palette pixels).
- Integrated `ScenarioLoader`: loads scenario metadata, sets scene music (`calm`), plays opening beats in sequence (resolving feeling via `SpriteResolver`, noting sprite and cues in `AudioDirector`, feeding typewriter).
- Conventions: UI components live on `CanvasLayer` (layer 2) so camera zoom/pan does not move the dialogue interface; background and character live in world space and zoom cohesively.
- Gotcha: native methods like `get_node_or_null` cannot be overridden in Godot 4.7 (treated as warning-error); provide direct property accessors (`text_box`, `input_box`, `chat_ui`, `character`, `fx`) and `find_component()`.
- Gotcha: `AudioDirector.begin_turn()` takes 0 arguments; set stage beforehand with `AudioDirector.set_stage(stage)`.

## P1.16 — Round 2 rework (2026-11-03)
- Addressed CON-1, DES-1 through DES-5, and CON-3.
- Gate C5 window sizing evaluated: set `window_width_override=384` and `window_height_override=688` in `project.godot`. 1× native launch fits a 1080p desktop with taskbar headroom; integer scaling scales cleanly to 2× on 1440p/4K.
- Wired `photosensitive` from `Settings` to `DateFX` (disables twitch flash) and forwarded scenario `ambience` to `AudioDirector.play_system()`.
- Re-captured stills after 25 frames (>400 ms) so Character's 140 ms crossfade settles completely at 100% opacity.
