# ART journal — P1

## P1.10 — Character scene + SpriteResolver T0–T1 (2026-11-02)
- Built `SpriteResolver` (autoload) and `Character.tscn/gd`: tier map read from `casting.tiers`, base table, min-tier/flag gates, sibling anti-repeat, fallback; 140 ms A/B crossfade; nine motion presets; four camera presets.
- `casting.json` stays the only table: added the `siblings` map to `build_casting.py` with validation and generated docs/10 §3.1; bridge re-run is 0-diff (66 files, manifest `a7602bcf8b0331f6`).
- Conventions: sprite id → `res://assets/sprites/leila/<basename>`; x2 art at scale 0.5 = 1:1 texels in the 384×688 viewport; `texture_filter=1` pinned on the Character root; camera presets min-fit their rect and clamp inside the frame.
- Gotcha: gdUnit4/GDScript lambdas capture scalars by value — async probes must write through a Dictionary or the assertion is vacuous (the first motion-test draft passed nothing).
- Gotcha: the bust camera reads the *current* sprite's `bust_crop_native`, and pivots must be recomputed on every swap before motion/camera; lean-in and face depend on `eyes_native`.
- Next: P1.11 connect `twitch_fired` → chromatic split and the glitch shader; P1.16 instantiate the scene, call `set_feeling` before `say`, bind `Settings.reduced_motion`; P2.14 owns path rules, dissonance and T2+ siblings.
