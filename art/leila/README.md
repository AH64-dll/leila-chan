# Leila-chan — pixel sprite set (HD)

31 sprites (00 base + 30 feelings), pixel art in the Leila palette.

- `px/` — native 384×688 RGBA. Use these in Godot with **Filter: Nearest** and scale ×2 (or any integer).
- `x2/` — the same at 768×1376 for tools/previews.
- `palette.json`, `leila.gpl` — every colour used, grouped by ramp (hair, dress, blouse, skin, eye, mouth, shade,
  white, pale, blush, line, outline, rim, steel, eye_white, face_shadow, fx, plus `fx_derived`: shades the coded
  effects derive from the base colours, e.g. 29's ×0.55 scanlines — the generator refuses used colours that are
  not a listed colour or a documented derivation).
- `sheet_faces.png`, `sheet_bodies.png` — contact sheets.

Built by `tools/art/leila_px.py` with `LEILA_SCALE=2` (cutout, normalise, face classes, pixel-down, recolour) and
`tools/art/leila_hd.py` (heart clip, per-sprite fixes, clean-up, glitch/aura effects). The originals in the project
root are never modified. The earlier 192×344 set is in `art/leila_legacy_1x/`.

Casting (which sprite, sound and music each feeling uses): `docs/10_CASTING.md` / `data/casting.json`.
