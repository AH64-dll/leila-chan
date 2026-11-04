# 10 — Casting: feeling → face → motion → voice → sound → music

> Generated from `tools/casting/build_casting.py` (also writes `data/casting.json`, the file the game loads).
> Every name below is validated against the stage gates (docs/02 §2), the audio map (`assets/audio/cue_map.json`)
> and the exported art (`art/leila/`). Re-run the script after any change.

## 1. How a beat is cast

The model only says `feeling` + `intensity` (and optionally `cue`, `music`, `fx`). The **CastingDirector** fills in
everything else from this table, so her face, body, voice, sounds and music always agree:

```
beat {feeling, intensity, cue?, say}
  ├─ sprite   = resolver(feeling, intensity, tier, path)        → §2 (+ path overrides §4;
  │              same sprite 3 beats in a row → siblings[f], docs/03 §3 step 4)
  ├─ motion   = feelings[f].motion[intensity]                   → Godot tween preset (docs/03 §4)
  ├─ voice    = voice_by_stage[stage]  pitched by feelings[f].voice (empty → no blips: she speaks in silence)
  ├─ cue      = model's cue if allowed, else (auto-fill, i ≥ 2, budget ok) random from tiers[t].cues
  ├─ fx       = model's fx if allowed, else (i = 3) first of tiers[t].fx
  ├─ music    = model's music, else after 2 beats of the same feeling → tiers[t].music (20 s hold)
  └─ on_enter = extra sounds/fx when certain sprites appear (§3)
```

Model-chosen values always win when they pass the gates; the table only fills gaps and keeps them coherent.
The `model_hint` column is appended to the feeling glosses in `rules.md`, so the model learns the pairing.

## 2. Feelings

Sprite cells are `i1–2 / i3`. Tiers: T0 = stage 0–1, T1 = 2, T2 = 3, T3 = 4–5.

| Feeling | V/A | Sprites T0 · T1 · T2 · T3 | Motion i1/i2/i3 | Voice | Model hint |
|---|---|---|---|---|---|
| **joy** | +3/2 | 01/01 · 01/01 · 01/22 · 22/22 | breathe/bounce/bounce | +3 st ×1.15 | giggle/laugh_soft; music playful |
| **warmth** | +2/0 | 02/02 · 02/02 · 02/02 · 05/05 | breathe/breathe/bounce | +1 st ×0.95 | hum/sigh; music calm |
| **playful** | +1/1 | 03/03 · 03/03 · 03/03 · 25/25 | breathe/bounce/bounce | +2 st ×1.1 | giggle; music playful |
| **proud** | +2/2 | 04/04 · 04/04 · 03/03 · 25/25 | breathe/bounce/bounce | +2 st ×1.05 | laugh_soft; fx sparkle |
| **shy** | +1/2 | 06/06 · 06/06 · 06/24 · 24/24 | bounce/bounce/tremble | +2 st ×1.25 | giggle/heartbeat; fx blush_glow |
| **love** | +3/2 | 06/01 · 06/06 · 24/24 · 24/24 | breathe/lean_in/lean_in | +1 st ×0.9 | heartbeat; music romantic; fx hearts |
| **curious** | +1/1 | 05/05 · 05/05 · 05/05 · 05/05 | breathe/bounce/lean_in | +2 st ×1.0 | hum; usually no cue |
| **confused** | +0/1 | 08/08 · 08/08 · 08/26 · 29/29 | breathe/breathe/shake | +1 st ×0.85 | hum; usually no cue |
| **surprised** | +0/3 | 11/11 · 11/11 · 11/26 · 26/26 | bounce/shake/shake | +4 st ×1.3 | gasp; fx shake_small |
| **nervous** | -1/2 | 13/13 · 13/12 · 13/28 · 28/28 | breathe/tremble/tremble | +1 st ×1.3 | heartbeat; music tense when it lasts |
| **sad** | -2/0 | 14/15 · 14/14 · 14/14 · 23/23 | sink/sink/sink | -2 st ×0.8 | sigh; music melancholy |
| **crying** | -2/1 | 15/16 · 15/16 · 16/16 · 16/16 | sink/tremble/tremble | -3 st ×0.75 | sniffle/sob; music melancholy |
| **angry** | -3/3 | 17/17 · 17/17 · 17/17 · 17/30 | shake/shake/shake | +1 st ×1.2 +3 dB | fx shake_small; music tense |
| **cold** | -1/0 | 07/07 · 07/07 · 07/07 · 25/25 | breathe/breathe/freeze | -1 st ×0.85 | sigh or none; music keep |
| **suspicious** | -1/1 | 09/09 · 09/09 · 09/09 · 25/25 | breathe/lean_in/lean_in | -1 st ×0.9 | hum; fx zoom_face |
| **disgusted** | -2/2 | 18/18 · 18/18 · 18/18 · 18/30 | shake/shake/shake | +0 st ×1.1 | sigh; fx shake_small |
| **bored** | -1/0 | 10/10 · 10/10 · 10/10 · 23/23 | breathe/sink/sink | -2 st ×0.7 | sigh; music calm |
| **tired** | -1/0 | 12/12 · 12/12 · 12/12 · 23/23 | sink/sink/sink | -2 st ×0.7 | sigh; music calm |
| **afraid** | -3/3 | 11/20 · 20/20 · 20/20 · 26/26 | tremble/tremble/tremble | +2 st ×1.4 | gasp/heartbeat; music tense |
| **pleading** | -2/3 | 19/19 · 19/19 · 19/19 · 19/19 | lean_in/tremble/tremble | +1 st ×1.2 | sniffle; fx zoom_face |
| **empty** | -2/0 | 07/07 · 10/10 · 23/23 · 23/29 | freeze/freeze/freeze | silent | no cue; music silence when it deepens |
| **manic** | +0/3 | 03/13 · 13/13 · 22/22 · 22/28 | bounce/twitch/twitch | +3 st ×1.5 | giggle; music playful |

Motion presets have no extra art per intensity (docs/03 §4): the displacement is scaled by
`casting.motion_intensity` (i1 ×0.6 · i2 ×1 · i3 ×1.4), with i2 = the doc's baseline. A beat's `motion_scale` travels in the
resolver packet, so bounce/shake/tremble/sink/lean-in/twitch all breathe more or less with the intensity.

### 2.1 Sound, music and screen per tier

| Feeling | Tier | Cue pool | Music | FX |
|---|---|---|---|---|
| joy | T0 | giggle, laugh_soft | playful | sparkle, hearts |
|  | T1 | giggle, laugh_soft | playful | sparkle |
|  | T2 | laugh_soft, music_box_note | music_box | sparkle, flicker |
|  | T3 | laugh_unhinged, music_box_note | distorted | vignette_red, flicker |
| warmth | T0 | hum, sigh | calm | blush_glow, sparkle |
|  | T1 | hum, music_box_note | calm | blush_glow |
|  | T2 | music_box_note, hum | music_box | blush_glow |
|  | T3 | music_box_note, breath_close | music_box | darken |
| playful | T0 | giggle | playful | sparkle |
|  | T1 | giggle, phone_buzz | playful | sparkle |
|  | T2 | giggle, whisper | playful | sparkle |
|  | T3 | whisper, laugh_unhinged | dread | darken |
| proud | T0 | laugh_soft | playful | sparkle, zoom_face |
|  | T1 | laugh_soft | playful | sparkle |
|  | T2 | laugh_soft, heartbeat | playful | zoom_face |
|  | T3 | laugh_unhinged | dread | zoom_face, darken |
| shy | T0 | giggle, gasp, heartbeat | romantic | blush_glow, hearts |
|  | T1 | giggle, heartbeat | romantic | blush_glow, hearts |
|  | T2 | heartbeat_fast, giggle | music_box | blush_glow |
|  | T3 | heartbeat_fast, breath_close | music_box | blush_glow, vignette_red |
| love | T0 | heartbeat, sigh, hum | romantic | hearts, blush_glow |
|  | T1 | heartbeat, music_box_note | romantic | hearts, blush_glow |
|  | T2 | heartbeat_fast, whisper | music_box | hearts, vignette_red |
|  | T3 | breath_close, heartbeat_fast | music_box | vignette_red, her_eyes |
| curious | T0 | hum, gasp | keep | sparkle |
|  | T1 | hum | keep | sparkle |
|  | T2 | whisper | keep | zoom_face |
|  | T3 | whisper, static | keep | zoom_face |
| confused | T0 | sigh, hum | keep | zoom_face |
|  | T1 | clock_tick | keep | zoom_face |
|  | T2 | static, clock_tick | tense | glitch |
|  | T3 | static | distorted | glitch, text_bleed |
| surprised | T0 | gasp | keep | shake_small, zoom_face |
|  | T1 | gasp, phone_buzz | keep | shake_small, zoom_face |
|  | T2 | gasp, glass_shatter, door_slam | tense | shake_big, zoom_face |
|  | T3 | glass_shatter, static, scream | silence | shake_big, invert_flash |
| nervous | T0 | gasp, heartbeat | calm | shake_small |
|  | T1 | heartbeat, clock_tick | tense | shake_small |
|  | T2 | heartbeat_fast, clock_tick | tense | flicker |
|  | T3 | heartbeat_fast, clock_tick, whisper | tense | flicker, glitch |
| sad | T0 | sigh, sniffle | melancholy | rain |
|  | T1 | sigh, sniffle, music_box_note | melancholy | rain |
|  | T2 | music_box_note, sigh | melancholy | rain, darken |
|  | T3 | music_box_note | silence | darken |
| crying | T0 | sniffle, sob | melancholy | rain |
|  | T1 | sob, sniffle | melancholy | rain |
|  | T2 | sob | melancholy | rain, darken |
|  | T3 | sob, whisper | music_box | darken, text_bleed |
| angry | T0 | sigh | keep | shake_small |
|  | T1 | knock | tense | shake_small |
|  | T2 | door_slam, glass_shatter | tense | shake_big, vignette_red |
|  | T3 | knife_draw, glass_shatter | dread | shake_big, vignette_red, her_eyes |
| cold | T0 | sigh | keep | — |
|  | T1 | sigh, clock_tick | keep | — |
|  | T2 | clock_tick | silence | darken |
|  | T3 | whisper, clock_tick | dread | darken |
| suspicious | T0 | hum | keep | zoom_face |
|  | T1 | phone_buzz, clock_tick | tense | zoom_face |
|  | T2 | whisper, knock | tense | zoom_face, vignette_red |
|  | T3 | breath_close, whisper | dread | her_eyes, vignette_red |
| disgusted | T0 | sigh | keep | shake_small |
|  | T1 | sigh | keep | shake_small |
|  | T2 | door_slam | tense | darken |
|  | T3 | knife_draw | dread | vignette_red |
| bored | T0 | sigh | calm | — |
|  | T1 | sigh, clock_tick | calm | — |
|  | T2 | clock_tick | silence | darken |
|  | T3 | clock_tick, static | silence | darken |
| tired | T0 | sigh | calm | — |
|  | T1 | sigh, clock_tick | melancholy | — |
|  | T2 | clock_tick | melancholy | darken |
|  | T3 | clock_tick, breath_close | dread | darken |
| afraid | T0 | gasp, heartbeat | keep | shake_small |
|  | T1 | gasp, heartbeat_fast | tense | shake_small |
|  | T2 | heartbeat_fast, knock | dread | flicker, darken |
|  | T3 | heartbeat_fast, static, scream | dread | flicker, glitch |
| pleading | T0 | sniffle, gasp | melancholy | zoom_face |
|  | T1 | sob, heartbeat | melancholy | zoom_face |
|  | T2 | sob, heartbeat_fast | music_box | zoom_face, vignette_red |
|  | T3 | sob, breath_close | music_box | her_eyes, text_bleed |
| empty | T0 | — | keep | — |
|  | T1 | clock_tick | calm | — |
|  | T2 | music_box_note | silence | darken |
|  | T3 | static, whisper | silence | darken, glitch |
| manic | T0 | giggle, laugh_soft | playful | shake_small |
|  | T1 | giggle | playful | shake_small |
|  | T2 | laugh_soft, heartbeat_fast, static | distorted | glitch |
|  | T3 | laugh_unhinged, static | distorted | glitch, invert_flash, text_bleed |

Cues `hum`, `sniffle` and `sob` are cast but have no files yet (voice-actor gap, docs/04 §8.4); until then the
AudioDirector skips them silently.

### 2.2 Screen-effect rules (docs/02 §2.3 + §5)

`fx.none` is the default (no effect). `gate` is the minimum stage; `cooldown_turns` is how many turns
after a firing stay locked (earliest refire = gap + 1); `max_per` is the doc's extra per-window cap.
FX.gd reads this table and drops over-gate/over-budget picks silently; the debug menu (F6) can force
any implemented effect.

Photosensitive mode changes the look, never the rule: `flicker` becomes a single dim instead of a flicker
(no luminance change faster than 3 Hz, docs/02 §2.3) and `invert_flash` is suppressed. Reduced motion
still cuts `shake_big` and `shake_small` — shakes are skipped, not softened.

| Effect | Gate stage | Cooldown (turns) | Extra cap |
|---|---|---|---|
| blush_glow | 0 | 3 | — |
| hearts | 0 | 3 | — |
| sparkle | 0 | 3 | — |
| shake_small | 0 | 3 | — |
| zoom_face | 0 | 3 | — |
| rain | 1 | 3 | — |
| shake_big | 3 | 3 | max 1 per 2 turns |
| flicker | 3 | 3 | — |
| darken | 3 | 3 | — |
| vignette_red | 3 | 3 | — |
| glitch | 3 | 3 | max 1 per 2 turns |
| text_bleed | 4 | 3 | — |
| invert_flash | 4 | 3 | — |
| her_eyes | 5 | 3 | — |
| none | 0 | — | — |

### 2.3 Stage baseline effects (docs/01 §3 + docs/03 §4)

The world itself drifts as the stage rises. These rows are not model picks, so they carry no gate and no
cooldown; FX.gd applies the row on every stage change and names it to the host. `desaturation` is the
screen's 0–1 drain: docs/01 §3 starts it at stage 3 ("backgrounds desaturate") and docs/03 §4 gives the
rate (`saturation × (1 − 0.15·stage)`, so stage 5 keeps 25%). The host ramps the value, so a transition
reads as a drain rather than a snap.

| Stage | Desaturation |
|---|---|
| 0 | 0.00 |
| 1 | 0.00 |
| 2 | 0.00 |
| 3 | 0.45 |
| 4 | 0.60 |
| 5 | 0.75 |

## 3. Sprite on-enter events

Extra sound, music, fx or motion the instant a sprite appears, on top of the beat's own casting. `cue_below_stage4`
and `fx_below_stage5` swap in the quieter variant under that stage; `budget` caps how often the effect may fire
(`1 reveal per scene` gates the sprite itself, `terminal climax only` withholds the `system` sting until stage 5).

| Sprite | Extra when it appears |
|---|---|
| 11 sudden_shock | system: stinger.soft |
| 16 bitter_breakdown | cue: sob |
| 20 paralyzing_terror | cue: heartbeat_fast; motion: tremble |
| 21 red_eyed_knife_mania | cue: knife_draw; system: stinger.mid; fx: vignette_red; music: dread; motion: lean_in; budget: 1 reveal per scene |
| 22 unhinged_jaw_laugh | cue: laugh_unhinged; cue_below_stage4: laugh_soft; motion: shake |
| 23 hollow_dead_eyed_void | music: silence; system: weird; motion: freeze |
| 24 obsessive_yandere_blush | cue: heartbeat; fx: hearts |
| 25 shadowed_psychosis | system: stinger.soft; fx: darken |
| 26 sanity_break_twitch | system: glitch; motion: twitch |
| 27 bloodstained_innocence | cue: music_box_note; music: music_box; flag: rival_gone |
| 28 manic_finger_biting | cue: clock_tick; motion: twitch |
| 29 glitching_distortion | cue: static; system: glitch, distort_layer; fx: glitch; motion: glitch; note: also the fallback face for invalid model output at T3 |
| 30 predatory_bloodlust | cue: heartbeat_fast; system: stinger.stage_change; fx: her_eyes; fx_below_stage5: vignette_red; music: dread; motion: lean_in; budget: terminal climax only |

### 3.1 Anti-repeat siblings

docs/03 §3 step 4: when one sprite would show on a third beat in a row, the resolver shows the feeling's sibling
instead. Siblings are healthy faces (ids 01–20, so a T0–T1 swap can never read as corruption) in the same mood
family; a swap never crosses the healthy/corrupt band.

| Feeling | Sibling |
|---|---|
| joy | 06 flustered_shyness |
| warmth | 05 pure_innocence |
| playful | 05 pure_innocence |
| proud | 01 radiant_joy |
| shy | 01 radiant_joy |
| love | 02 gentle_relief |
| curious | 01 radiant_joy |
| confused | 09 suspicious_glare |
| surprised | 08 deep_confusion |
| nervous | 06 flustered_shyness |
| sad | 12 exhausted_fatigue |
| crying | 14 quiet_melancholy |
| angry | 18 visceral_disgust |
| cold | 10 bored_apathy |
| suspicious | 07 stoic_coldness |
| disgusted | 17 fierce_anger |
| bored | 12 exhausted_fatigue |
| tired | 10 bored_apathy |
| afraid | 13 nervous_anxiety |
| pleading | 15 tearful_sorrow |
| empty | 14 quiet_melancholy |
| manic | 11 sudden_shock |

### 3.2 Corrupt-band siblings (T2+)

A corrupted sprite cannot swap to a healthy one (that would lie about the state), so the corruption band has its
own table: one sibling per sprite, same path signature or mood family, addressed by sprite id. A sibling whose
own `tiers` start above the current tier is skipped, so the beat simply repeats rather than jump forward.

| Sprite | Tiers | Sibling |
|---|---|---|
| 21 red_eyed_knife_mania | T3 | 24 obsessive_yandere_blush |
| 22 unhinged_jaw_laugh | T2–T3 | 26 sanity_break_twitch |
| 23 hollow_dead_eyed_void | T2–T3 | 29 glitching_distortion |
| 24 obsessive_yandere_blush | T2–T3 | 28 manic_finger_biting |
| 25 shadowed_psychosis | T3 | 29 glitching_distortion |
| 26 sanity_break_twitch | T2–T3 | 28 manic_finger_biting |
| 27 bloodstained_innocence | T3 | 24 obsessive_yandere_blush |
| 28 manic_finger_biting | T2–T3 | 26 sanity_break_twitch |
| 29 glitching_distortion | T3 | 23 hollow_dead_eyed_void |
| 30 predatory_bloodlust | T3 | 21 red_eyed_knife_mania |

## 4. Paths

| Path | Overrides (T2–T3) | Rule | Music / cue bias |
|---|---|---|---|
| YANDERE | love→24, angry→21, suspicious→28, joy→22 |  | music_box / heartbeat_fast, breath_close |
| SPLIT | crying→16, pleading→19 | alternate when beat valence flips | tense / sob, door_slam |
| TSUN | playful→03, cold→07, disgusted→18, angry→17 |  | keep / sigh, door_slam |
| HOLLOW | — | sprite changes only on intensity 3 | silence / clock_tick, music_box_note |
| AWAKE | confused→29, surprised→26, cold→25, manic→22 | glitch shader on every sprite change | distorted / static |
| ANCHOR | — | keeps healthy sprites; relapse beat uses 26/22 once, then 02 | calm / hum, sigh |

## 5. Voice by stage

| Stage | Blip pool (`cue_map.json` system group) |
|---|---|
| 0 | `voice_blip.stage0_2` |
| 1 | `voice_blip.stage0_2` |
| 2 | `voice_blip.stage0_2` |
| 3 | `voice_blip.stage3` |
| 4 | `voice_blip.stage4` |
| 5 | `voice_blip.stage5` |
| AWAKE>=3 | `voice_blip.awake` |

## 6. Sprite reference

All sprites: native 384×688 (`art/leila/px`), display 768×1376 (`art/leila/x2`, nearest-neighbour ×2).
Eye points (native px) drive the glow/`her_eyes` shaders; `bust_crop_native` is the `zoom_face` / intensity-3 frame.

| # | Key | Face (eyes · mouth · extras) | Cast by feelings |
|---|---|---|---|
| 00 | base_reference | open · smile ·  | special (idle / flag / fallback) |
| 01 | radiant_joy | happy · laugh · blush | joy, love |
| 02 | gentle_relief | soft · smile · blush | warmth |
| 03 | playful_smugness | happy/narrow · smile ·  | manic, playful, proud |
| 04 | confident_pride | soft · smile ·  | proud |
| 05 | pure_innocence | open · small_o · blush | curious, warmth |
| 06 | flustered_shyness | soft · wavy · blush_heavy, sweat | love, shy |
| 07 | stoic_coldness | narrow · flat ·  | cold, empty |
| 08 | deep_confusion | open/soft · pout · sweat | confused |
| 09 | suspicious_glare | narrow · pout ·  | suspicious |
| 10 | bored_apathy | tired · flat ·  | bored, empty |
| 11 | sudden_shock | wide · shock ·  | afraid, surprised |
| 12 | exhausted_fatigue | tired · small_o · eyebags | nervous, tired |
| 13 | nervous_anxiety | open · wavy · sweat | manic, nervous |
| 14 | quiet_melancholy | soft · frown ·  | sad |
| 15 | tearful_sorrow | tear · sad_open · tears | crying, sad |
| 16 | bitter_breakdown | shut · grimace · tears | crying |
| 17 | fierce_anger | furious · shout ·  | angry |
| 18 | visceral_disgust | narrow/soft · tongue ·  | disgusted |
| 19 | desperate_pleading | tear · sad_open · tears, blush | pleading |
| 20 | paralyzing_terror | wide · shock · sweat, tears | afraid |
| 21 | red_eyed_knife_mania | glow · grin ·  | special (idle / flag / fallback) |
| 22 | unhinged_jaw_laugh | manic · jaw ·  | joy, manic |
| 23 | hollow_dead_eyed_void | dead · flat ·  | bored, empty, sad, tired |
| 24 | obsessive_yandere_blush | heart · open_smile · blush_heavy | love, shy |
| 25 | shadowed_psychosis | glow · smile ·  | cold, playful, proud, suspicious |
| 26 | sanity_break_twitch | manic/wide · grin · sweat | afraid, confused, surprised |
| 27 | bloodstained_innocence | open · smile · blood | special (idle / flag / fallback) |
| 28 | manic_finger_biting | manic · grimace ·  | manic, nervous |
| 29 | glitching_distortion | dead/glow · grin ·  | confused, empty |
| 30 | predatory_bloodlust | glow · fangs · blood | angry, disgusted |
