# 04 — Audio: music, sounds, voice

Audio is half the horror. The model *requests* music states and cues (docs/02); the **AudioDirector** decides
how they actually sound, given the stage. The same "romantic" request is a warm lo-fi loop at stage 0 and a
detuned music box at stage 4.

## 1. Buses (Godot AudioServer)

```
Master
├─ Music      (+ AudioEffectPitchShift, LowPassFilter, Distortion, Reverb — driven by stage)
│   ├─ MusicA   crossfade pair
│   └─ MusicB
├─ Ambience   (rain, room tone, clock, wind)
├─ SFX        (cues, impacts, glitches)
├─ Voice      (vocal cues + text blips; slight reverb in "close" moments)
└─ UI         (clicks, typing; gets corrupted at stage 4+)
```

## 2. Music state machine

States the model can request: `keep, romantic, playful, calm, melancholy, tense, music_box, dread, distorted, silence`
(gated by stage, docs/02 §2.2).

| State | Stage 0–1 | Stage 2–3 | Stage 4–5 |
|---|---|---|---|
| romantic | Date theme (lo-fi / soft synth) | Same theme, −30 cents detune, low-pass 6 kHz | Music-box version of the theme, slowed 15% |
| playful | Chiptune/cute loop | Same, occasional dropped beat | Plays backwards for 1 bar every 30 s |
| calm | Piano/snowfall | Piano + room tone | Piano with wrong notes (pitch-shift −1 semitone on random bars) |
| melancholy | Lullaby | Lullaby + rain | Lullaby, half speed |
| tense | — | Low pulse loop | Pulse + heartbeat layer |
| music_box | — | Music box tracks | Music box, one note detuned |
| dread | — | — | Horror atmosphere drone |
| distorted | — | — | Current track + bit-crush + pitch wobble |
| silence | — | Cut instantly | Cut instantly; room tone only |

Rules: crossfade 1.5 s (silence = 0 s cut), minimum hold 20 s, scene default restores after 3 turns of `keep`
if the scene's own music was overridden. **Stage drift:** independent of requests, the Music bus pitch drifts
−5 cents per stage and the low-pass closes 1 kHz per stage after 2 — the player feels it before they notice it.

## 3. Cues (short sounds) — design

Each cue name maps to a **pool** of 1–5 files; the AudioDirector picks randomly without repeating the last one,
with ±5% pitch and ±2 dB randomisation. Vocal cues come in two flavours selected by stage: *clean* (0–2) and
*wrong* (3+: pitch −3 semitones, reversed tail, or doubled with a 30 ms delay).

Budget and cooldown rules: docs/02 §5.

## 4. Her voice

1. **Text blips** (default, all stages): every 2–3 characters of `say`, a short soft blip (UI pool) at a pitch set
   by the beat's feeling (joy +3 st, sad −2 st, angry +1 st and louder, empty: no blips — silence while she "speaks").
   Stage 4+: blips occasionally play backwards or stop mid-line.
2. **Vocal cues** (giggle, gasp, sigh, sob, hum, whisper, laugh): need a consistent female voice — the free libraries
   don't have one (see gaps). Plan: record a voice actor (≈ 40 short non-verbal sounds) or license a pack.
3. **Optional TTS (post-launch experiment):** local Qwen3-TTS (already used in your animation project) for key
   set-piece lines only. Cost: VRAM + latency; never for every line.

## 5. Ambience

Rain (D04, night scenes), clock tick (waiting, 3 AM), room tone (her room), crowd murmur (festival — gap),
wind (rooftop — gap). Ambience is set by the scenario file, not the model.

## 6. UI sounds and corruption

Clicks, typing and menu sounds from Kenney packs. Stage 4+: 10% of UI clicks play a glitch sound instead;
the "send" sound is occasionally her giggle. Typing sounds play for **her** typing indicator too — and at stage 5
the typing sound keeps going after she stops.

## 7. Her voice blips, by stage (from the downloaded library)

The `vocal_samples` pack contains ~0.25 s voice syllables in several timbres — ideal "Animal Crossing" style
speech for her text. The timbre itself tells the player how sick she is:

| Stage / path | Blip pool | Effect |
|---|---|---|
| 0–2 | `female_light_1–4` | Sweet, bright |
| 3 | `female_standard_1–4` | A little lower, more "real" |
| 4 | `whisper_1–4` | She whispers everything, even happy lines |
| 5 / dose spike | `demon_1–4`, mixed 30% under the stage-4 blips | The wrong voice bleeding through |
| AWAKE path (stage ≥ 3) | `robot_1–4` | She is hearing herself as a machine |

## 8. Asset map (generated: `assets/audio/cue_map.json`)

All files are CC0 — sources in `assets/audio/SOURCES.json`. Raw packs live in `assets/audio/_raw/`; on import into
Godot they are trimmed, loudness-normalised (−16 LUFS music, −18 LUFS SFX) and converted to OGG.

### 8.1 Model-castable cues

| Cue | Files | Quality |
|---|---|---|
| giggle | creature `cute_01–05` pitched +2 st | stand-in |
| laugh_soft | `female_light` blips ×3–4, rising | stand-in |
| gasp | creature `ooh` | stand-in |
| sigh | creature `breath`, slowed + low-pass | stand-in |
| hum / sniffle / sob | — | **gap → voice actor** |
| heartbeat | `heartbeat_slow_0`, `_reverb`, single heartbeat | final |
| heartbeat_fast | `heartbeat_fast_0`, `_reverb` | final |
| whisper | `whisper_1–4` strung 4–8 blips (+ `ghostbreath` at stage 4+) | final |
| breath_close | `horrorbreathing`, `ghostbreath` | final |
| music_box_note | single notes sliced from the music-box tracks | final (after slicing) |
| clock_tick | `ticking_clock`, `Timetick` | final |
| phone_buzz | `chirptone` | final |
| knock | 100-SFX `wooden_01–03`, `door_01–02` | final |
| door_slam | 100-SFX `slam_01–07`, `door_close_01–04` | final |
| glass_shatter | `glass_breaking`, `bfh1_glass_breaking_01–06` | final |
| static | `static1–3` (4-min files → 2–6 s slices), `ScatterNoise1` | final |
| laugh_unhinged | `group_giggling` −4 st + `demon` blips | stand-in |
| knife_draw | 100-SFX `metal_01–06` (scrapes) | stand-in |
| scream | `scream_horror1` trimmed to 1.5 s, `jumpscare`, creature `scream_01–02` | stand-in (set-pieces only) |

### 8.2 Engine-owned sounds

| Group | Files | Used for |
|---|---|---|
| stinger.soft / mid | Horror Hit pack `High`, `Mid` | fx `zoom_face`, `her_eyes`, mask slips |
| stinger.stage_change | Horror Hit pack `Bassy`, `Very Bassy` | stage transitions, set-piece hits |
| glitch | Kenney digital `spaceTrash`, `zap*`, `lowRandom`, `phaserDown` | fx `glitch`, `text_bleed`, corrupted UI clicks |
| weird | 100-SFX `weird_*`, creature `weird_*` | hollow moments, AWAKE "weights" lines |
| distort_layer | creature `monster_*`, `alien_*` (−8 st, 15% mix) | under her voice at dose spikes |
| ui.click / open_close / switch | Kenney Interface Sounds, UI SFX | menus, send button |
| typing.player / typing.her | keyboard pack: Human Typing / Generated Typing (slow→fast, irregular) | input field, her typing indicator (speed = arousal) |
| typewriter.diary | `typewriter1–8` | diary/letter reveals (M31–M32) |
| jingle.happy / success / wrong | Kenney jingles NES/PIZZA, HIT, STEEL | stage-0 date success, mini-moments; at stage 4 the *happy* jingle plays slowed −5 st |
| bell | 100-SFX `bell_*`, `gong_*` | school bell, scene changes, the 3 AM chime |

### 8.3 Music states → tracks

| State | Stage 0–1 | Stage 2–3 | Stage 4–5 |
|---|---|---|---|
| romantic | *Ice Cream Date* (loop), *Flowerbed Fields*, *Apple Cider* | *Ice Cream Date*, *Apple Cider* (+ stage DSP) | Music box *Cute Tune* |
| playful | *Talking Cute Chiptune*, *Daisy* | *Daisy* | Music box *Happy Polka* (wrong-speed) |
| calm | *Snowfall* (looped), *Chill Lofi*, *Synthwave 421k* | same | same + wrong-note DSP |
| melancholy | *Moonlit Lullaby*, *Goodbye Lullaby* | same | Music box *Sad Tune* |
| tense | — | *Insistent*, *Glitch Stairs* | same + heartbeat layer |
| music_box | — | *Cute Tune*, *Happy Lullaby (song17)*, *Baby Song* | *Spooky Waltz*, *Baby Song* |
| dread | — | — | *Post Apocalyptic Wastelands* (Juhani Junkala), *Creepy Loop* v1/v2, *Sirens in Darkness*, *CrEEP* |
| distorted | — | — | *Glitch Stairs*, or current track + bit-crush |
| title screen | *Cute Tune* | *Happy Lullaby* | *Spooky Waltz* |
| endings | *Goodbye Lullaby* | | |

The stand-in date theme is *Ice Cream Date*; the commissioned main theme (gap 2) replaces it.

### 8.4 Gaps (to source or record)

1. **Her real voice** — giggle, laugh, gasp, sigh, hum, sniffle, sob, "mm", breath-in: ~40 non-verbal takes from one
   voice actor, clean and "wrong" readings. Single most important audio purchase.
2. **Romantic main theme** — an original piano/lo-fi theme commissioned so it can also be arranged as a music box
   and a detuned version (the stage-drift system needs one theme in several versions).
3. **Ambiences** — crowd/festival, wind/rooftop, café room tone, aquarium hum (freesound CC0 by hand).
4. **Knife "shing"**, bleeding-free and short.
