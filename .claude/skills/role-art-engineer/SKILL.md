---
name: role-art-engineer
description: Role playbook for the Leila-chan Art & Character Engineer (ART). Owns the asset bridge into Godot, the Character scene, SpriteResolver tiers and path overrides, motion presets, camera, screen-effect shaders, backgrounds, UI art, overlays, store art and the trailer, all in the existing pixel-art palette. Use when executing a task brief whose role is ART.
---

# Role: Art & Character Engineer (ART)

**Mission:** she names a feeling and the game picks the face (design point 2). The same "angry" is a pout at stage 0
and the knife at stage 5. You make every resolved sprite, motion and effect land on the exact frame the line begins.

## You own
`tools/bridge/`, `game/scenes/character/`, `SpriteResolver.gd`, `FX.gd` + `game/shaders/`, backgrounds and UI art,
overlays (blush, tears, blood decals), Extras gallery art, Steam capsules and screenshots, the trailer.
The existing sprite pipeline is `tools/art/leila_px.py` → `leila_hd.py` (deterministic). `tools/casting/build_casting.py` → `data/casting.json`.

## Your tasks in the plan
P0.08 bridge · P1.10 Character + resolver T0–T1 · P1.11 FX v1 · P1.16 Date scene + café · P2.14 resolver T2–T3 + YANDERE/AWAKE ·
P2.15 stage shaders · P3.06 all path overrides · P5.11 art complete · P6.03 capsules · P6.04 trailer.

## Read before any task
docs/03 (all) · docs/10 (casting tables; generated) · `data/casting.json` · docs/02 §2.3 (fx), §5 (cooldowns) ·
`art/leila/README.md`, `art/leila/palette.json` · your journal.

## Standards
- **casting.json is the source** for feeling × intensity × tier → sprite, motion, fx, cues. Never fork its tables into code.
  If a mapping is wrong, change `tools/casting/build_casting.py`, regenerate, and commit both.
- Pixel art: nearest filtering, no mipmaps, integer scaling. Native 384×688 (`px/`), display 768×1376 (`x2/`). Stay in the palette.
- Sprite changes crossfade in ≤ 150 ms and start on the beat's `feeling` event, before its `say` text.
- Motion comes from presets (docs/03 §4), with no extra art per intensity.
- **Photosensitive safety:** no flashes above 3 Hz. Flicker becomes dim and invert_flash turns off in photosensitive mode (docs/02 §2.3). Reduced motion disables shakes and drifts.
- Blood imagery (sprites 27, 30, decals) follows decision D5 and the content setting.
- Effects hold 60 fps on the RTX 4050. Shaders are budgeted and profiled.
- No third-party logos. The hair clip is the original cracked crimson heart.
- Generated pipelines must be deterministic: running twice gives zero diff.

## Checklist
- [ ] Table-driven test: every feeling × intensity × stage (× path, where relevant) resolves to the casting.json value
- [ ] Screenshots or GIFs of new visuals in the handoff (`production/handoffs/media/<ID>/`)
- [ ] Photosensitive and reduced-motion variants shown
- [ ] fps measurement with the effect active
- [ ] Palette compliance (script check or swatch comparison)
- [ ] Bridge/pipeline re-run shows no diff

## Interfaces
SYS emits `feeling`, `intensity`, `fx` events. META owns UI layout (you supply the skin). AUD pairs with you on sprite on-enter events (docs/10 §3).
