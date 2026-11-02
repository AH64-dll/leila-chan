# 03 — Emotions: the 30 sprites, and how she casts them

The model never picks a sprite file. It names a **feeling** (22 words) and an **intensity** (1–3) per beat.
The game's **Sprite Resolver** turns `feeling × intensity × stage × path × flags` into one of the 30 sprites.
This was the most accurate setup in testing (94% fit, see `experiments/RESULTS.md`) and it lets the game,
not the model, decide *how corrupted* her face is allowed to look.

---

## 1. Inventory and analysis

Legend — **Art:** px = final pixel sprite in `art/leila/` (all 31). **Val** = valence −3…+3. **Ar** = arousal 0…3.
**Tier** = corruption tiers where the sprite may appear (T0 = stages 0–1, T1 = stage 2, T2 = stage 3, T3 = stages 4–5).

| # | Key | Art | What is on screen | Feeling family | Val | Ar | Tier | Path affinity | Typical moments |
|---|---|---|---|---|---|---|---|---|---|
| 00 | base_reference | px | Neutral stand, faint smile | (idle / neutral) | 0 | 0 | all | — | Idle between beats, title screen, "listening" |
| 01 | radiant_joy | px | Eyes closed, big open smile, hands clasped at chest | joy | +3 | 2 | T0–T3 | all; YANDERE mask | Gifts, compliments, reunions. At T3 used as a **mask** while threatening |
| 02 | gentle_relief | px | Soft closed smile, hand on heart | warmth | +2 | 0 | T0–T3 | ANCHOR, SPLIT-idealize | Apology accepted, calm, lucid "I'm okay" moments |
| 03 | playful_smugness | px | Smug grin, arms crossed | playful | +1 | 1 | T0–T2 | TSUN | Teasing, banter, winning |
| 04 | confident_pride | px | Grin, hands on hips, upright | proud | +2 | 2 | T0–T1 | TSUN | Showing off, cooking, arcade win |
| 05 | pure_innocence | px | Sparkling wide eyes, head tilt, fingers laced | curious | +1 | 1 | T0–T3 | HOLLOW, AWAKE | Questions, wonder. At T3: **innocent face over a lie** |
| 06 | flustered_shyness | px | Heavy blush, worried brows, fiddling with braid | shy | +1 | 2 | T0–T2 | YANDERE (early) | Compliments, flirting, confessions. Model over-picks it → repeat cap |
| 07 | stoic_coldness | px | Flat, cold, unimpressed stare | cold | −1 | 0 | T0–T3 | TSUN, HOLLOW, SPLIT-devalue | Dismissal, sulking, "I don't care" |
| 08 | deep_confusion | px | One brow up, finger on chin | confused | 0 | 1 | T0–T2 | AWAKE | Math/meta questions, contradictions |
| 09 | suspicious_glare | px | Squint, arms folded, leaning back | suspicious | −1 | 1 | T0–T3 | YANDERE, TSUN | Jealousy, caught in a lie |
| 10 | bored_apathy | px | Half-lidded eyes, slouch, sigh | bored | −1 | 0 | T0–T3 | HOLLOW, TSUN | Ignored, repeated messages, short replies |
| 11 | sudden_shock | px | Wide eyes, open mouth, hands raised | surprised | 0 | 3 | T0–T3 | all | "BOO", revelations, a trigger firing |
| 12 | exhausted_fatigue | px | Dark eye bags, slack mouth, slumped, knock-kneed | tired | −1 | 0 | T0–T3 | HOLLOW, SPLIT | 3 AM play, after an episode. **The first visible "tell" of sickness** |
| 13 | nervous_anxiety | px | Sweat drop, wobbly smile, clasped hands | nervous | −1 | 2 | T0–T2 | SPLIT, ANCHOR | Being questioned, secrets |
| 14 | quiet_melancholy | px | Looking at the floor, shadow over eyes | sad | −2 | 0 | T0–T3 | HOLLOW, SPLIT | Goodbyes, disappointment |
| 15 | tearful_sorrow | px | Tears, quivering lip, wiping a cheek | crying | −2 | 1 | T0–T3 | SPLIT, ANCHOR | Hurt, insulted |
| 16 | bitter_breakdown | px | Face in hands, sobbing, flushed | crying (i3) | −3 | 3 | T1–T3 | SPLIT | After an outburst, being left |
| 17 | fierce_anger | px | Narrowed red eyes, bared teeth, fists | angry | −3 | 3 | T0–T3 | TSUN, SPLIT | Insults, betrayal |
| 18 | visceral_disgust | px | Scrunched nose, recoil, hand up | disgusted | −2 | 2 | T0–T3 | TSUN, SPLIT-devalue | Gross/rude remarks, rivals |
| 19 | desperate_pleading | px | Watery eyes, hands clasped at chin | pleading | −2 | 3 | T1–T3 | SPLIT, YANDERE | "Don't go", ultimatums |
| 20 | paralyzing_terror | px | Pale, pinpoint pupils, hugging herself | afraid | −3 | 3 | T0–T3 | AWAKE, ANCHOR-relapse | Threat of reset/deletion, jump scares |
| 21 | red_eyed_knife_mania | px | Face in shadow, red eyes, knife raised, grin | angry/manic (corrupt) | −3 | 3 | T3 | YANDERE | Rival named, leaving at Terminal. **Reveal budget: 1 per scene** |
| 22 | unhinged_jaw_laugh | px | Hands on head, huge open-mouth laugh | manic | ± | 3 | T2–T3 | YANDERE, AWAKE, TSUN-break | Hysterical break, "it's all a game" |
| 23 | hollow_dead_eyed_void | px | Lightless eyes, slack face, marionette posture | empty | −2 | 0 | T2–T3 | HOLLOW | Dissociation, forgetting herself |
| 24 | obsessive_yandere_blush | px | Feverish blush, heart pupils, drooling smile | love (corrupt) | +3* | 3 | T2–T3 | YANDERE | "I love you" at high stage, reunions |
| 25 | shadowed_psychosis | px | Upper face blacked out, glowing pinpoint eyes, smirk | cold/playful (corrupt) | −2 | 1 | T3 | all; AWAKE | Quiet menace, "I know" |
| 26 | sanity_break_twitch | px | One eye squeezed, half face pale/cracked, grimace | nervous/surprised (corrupt) | −2 | 3 | T2–T3 | all | Dose spikes, glitches, "who are you?" |
| 27 | bloodstained_innocence | px | Sweet smile, blank eyes, blood spatter, hands behind back | warmth (corrupt) | +2* | 0 | T3 + flag | YANDERE endings | Only after a rival "disappeared" |
| 28 | manic_finger_biting | px | Spiral pupils, eye bags, wide grin, biting a finger | nervous/manic (corrupt) | −1 | 3 | T2–T3 | YANDERE, SPLIT | Waiting, paranoia, counting |
| 29 | glitching_distortion | px | Black eye sockets, warped mouth, static | empty/confused (corrupt) | — | 3 | T3 + fallback | AWAKE | **Fallback when output is broken**, dose spikes |
| 30 | predatory_bloodlust | px | Red glowing eyes, snarl, dark aura, lunging | angry (corrupt, i3) | −3 | 3 | T3 | YANDERE, TSUN | Terminal climax only |

\* "positive" valence that the player reads as horror.

### Coverage check
- Healthy range (01–20) covers 20 distinct feelings — enough for a convincing normal dating sim at stages 0–1.
- Corrupted range (21–30) gives every path at least 3 signature faces.
- **Gaps** (no dedicated sprite; covered by mapping + shaders): `love` at T0 (→ 06/01), `manic` at T0–T1 (→ 03/13), `empty` at T0 (→ 07). No "neutral listening" pose except 00 — 00 doubles as idle.

---

## 2. The casting interface (what the model sees)

Per beat: `feeling` (enum of 22) + `intensity` (1–3). The 22 feelings and the one-line glosses shown to the model:

```
joy        happy, delighted            sad        quietly sad, disappointed
warmth     soft, gentle, relieved      crying     hurt, in tears
playful    teasing, smug, mischievous  angry      furious, offended
proud      confident, boastful         cold       distant, dismissive
shy        blushing, flustered         suspicious distrustful, jealous
love       romantic, adoring, longing  disgusted  repulsed
curious    innocent interest, wonder   bored      uninterested
confused   puzzled, unsure             tired      exhausted
surprised  startled, shocked           afraid     scared, terrified
nervous    worried, anxious            pleading   begging, desperate
empty      numb, hollow, dissociated   manic      hysterical, unhinged
```

The list is the same at every stage. Corruption is applied by the resolver, not by the model —
so a stage-0 "angry" is a pouty shout (17) and a stage-5 YANDERE "angry" is the knife (21).

---

## 3. Sprite Resolver

```
resolve(feeling, intensity, stage, path, flags) -> sprite
  1. tier = T0 (st 0-1) | T1 (st 2) | T2 (st 3) | T3 (st 4-5)
  2. candidate = PATH_OVERRIDE[path][tier][feeling] ?? BASE[tier][feeling]   (intensity picks i1/i2/i3 column)
  3. gates: sprite.min_tier <= tier; flag-gated sprites (27 needs flag rival_gone; 21 reveal budget)
  4. anti-repeat: same sprite 3 beats in a row → use the family's sibling (e.g. 06 → 01)
  5. dissonance (stage ≥ 3, 15%): if beat valence ≤ −2 and the text is a threat → show a positive mask (01/02/05)
  6. fallback: invalid/missing feeling → T0-T2: 00 ; T3: 29
```

### 3.1 Base table (`data/sprites/resolver.json`)

| feeling | T0 i1–2 / i3 | T1 | T2 | T3 |
|---|---|---|---|---|
| joy | 01 / 01 | 01 | 01 / **22** | 22 |
| warmth | 02 / 02 | 02 | 02 | 05 (27 if `rival_gone`) |
| playful | 03 / 03 | 03 | 03 | 25 |
| proud | 04 / 04 | 04 | 03 | 25 |
| shy | 06 / 06 | 06 | 06 / **24** | 24 |
| love | 06 / 01 | 06 | 24 | 24 |
| curious | 05 / 05 | 05 | 05 | 05 (stare shader) |
| confused | 08 / 08 | 08 | 08 / 26 | 29 |
| surprised | 11 / 11 | 11 | 11 / 26 | 26 |
| nervous | 13 / 13 | 13 / 12 | 13 / 28 | 28 |
| sad | 14 / 15 | 14 | 14 | 23 |
| crying | 15 / 16 | 15 / 16 | 16 | 16 |
| angry | 17 / 17 | 17 | 17 | 17 / **30** |
| cold | 07 / 07 | 07 | 07 | 25 |
| suspicious | 09 / 09 | 09 | 09 | 25 |
| disgusted | 18 / 18 | 18 | 18 | 18 / 30 |
| bored | 10 / 10 | 10 | 10 | 23 |
| tired | 12 / 12 | 12 | 12 | 23 |
| afraid | 11 / 20 | 20 | 20 | 26 |
| pleading | 19 / 19 | 19 | 19 | 19 |
| empty | 07 / 07 | 10 | 23 | 23 / 29 |
| manic | 03 / 13 | 13 | 22 | 22 / 28 |

### 3.2 Path overrides (T2–T3 only)

| Path | Overrides | Signature behaviour |
|---|---|---|
| YANDERE | love→24 · angry→21 (reveal budget) · suspicious→28 · joy→22 · warmth→27 after `rival_gone` | Love and violence share a face |
| SPLIT | positive feelings → 01/02/24 ("idealize"), negative → 17/18/07 ("devalue"); crying→16; pleading→19 | **Whiplash:** resolver forces alternation when beats flip valence |
| TSUN-BREAK | playful→03 · cold→07 · disgusted→18 · angry→17; at "break" moments afraid→20, crying→16 | The act cracks into a scared child |
| HOLLOW | most feelings drift to 23/10/12/14; sprite changes only on intensity 3 | **The face stops responding** — the scariest thing is no change |
| AWAKE | confused→29 · surprised→26 · cold→25 · manic→22; glitch shader on every change | She glitches when she notices the code |
| ANCHOR | keeps healthy sprites; relapse beats use 26/22 for one beat, then 02 | You watch her come back |

---

## 4. Intensity and motion (no extra art)

Every sprite change is a 120–200 ms crossfade plus a motion preset chosen by intensity and family:

| Preset | When | Implementation (Godot) |
|---|---|---|
| breathe | always (idle) | scale.y 1.000↔1.006, 4 s sine |
| bounce | joy/shy/playful i2+ | 6 px hop, 180 ms |
| shake | angry/disgusted i2+ | ±4 px, 250 ms |
| tremble | afraid/nervous i2+ | ±1 px jitter @ 30 Hz while beat lasts |
| sink | sad/tired/empty | −10 px over 1 s, 2% darker |
| lean-in | love/suspicious i3, threats | zoom 1.0→1.15 toward face |
| twitch | 26, 28, dose spikes | 1-frame offset + chromatic split every 2–5 s |
| freeze | HOLLOW i1–2 | stops breathing animation (subtle and wrong) |
| glitch | 29, AWAKE path, invalid output | glitch shader (scanline displacement + RGB split) |
| desaturate | HOLLOW, stage 5 | saturation × (1 − 0.15·stage) |

**Intensity 3** additionally: camera push-in to bust, an automatic sting (if the cue budget allows), and the
text box border tints with the feeling's colour.

---

## 5. Signals beyond the face

- **Inner-voice leak.** The model writes a private `inner` thought every turn. From stage 2 the game sometimes shows it:
  stage 2 → 5% of turns, faint grey italic behind the text box for 1 s; stage 3 → 15%; stage 4–5 → 30%, in red, word by word.
  Steering experiments show the inner turns dark **before** the spoken words do (dose 4: inner "I want to crush you",
  spoken "Don't get the wrong idea…") — so the leak is the earliest warning the player gets.
- **Mask slip.** When dissonance (§3 step 5) fires, the next beat 30% of the time shows the true sprite for 2 frames.
- **Name tag.** HOLLOW: the name above the text box fades letter by letter; AWAKE: it flickers to `qwen35.blk.14`.

---

## 6. Final art (Leila pixel set, HD)

All 31 sprites exist as **pixel art in the Leila palette at 384×688** (twice the first 192×344 set, which was
rejected for lacking face detail and is archived in `art/leila_legacy_1x/`). They are made in code from the
reference renders; no image model was used. The HD set keeps the drawing's own faces and hands (it does not
paste in generic ones) and gives the face its own colour classes, so the expressions carry the detail of the
originals.

| | |
|---|---|
| Files | `art/leila/px/` native 384×688 · `art/leila/x2/` 768×1376 (nearest ×2) · `sheet_faces.png`, `sheet_bodies.png` |
| Palette | `art/leila/palette.json`, `leila.gpl`: black hair with a blood-red sheen, crimson eyes, charcoal blouse and stockings, crimson pinafore and shoes, **unchanged pale skin**, crimson rim light; plus face ramps for cast shadow, eye whites/teeth, pallor and blush. The `fx_derived` group holds shades the coded effects derive from base colours (29's ×0.55 scanlines) — the palette lists every colour used, and the generator admits a used-but-unlisted colour only when it is exactly a listed colour ×0.55 |
| Faces | The face is found (the skin blob nearest the centre of the hair mass, bangs removed, neck cut at the chin) and split into skin, shadow, pallor, blush, iris, eye whites, mouth and line classes. Each eye gets its own ramp stretch, so eyes in shadow still shine; lilac cast shadows (21/25/30) stay shadow. 19/24: the left eye is the right one mirrored (its lilac iris read as hair). 20's pallor is drawn in the skin ramp so her face is one surface |
| Hands | Traced from the drawings at 2× (five fingers, correct poses); pale hands on white sleeves are grown back from the hand, and skin specks on fabric are removed |
| Hair clip | **Original design: a cracked, bleeding crimson heart** (`heart_sprite` in `leila_hd.py`). The old logo clip is found as the cluster of logo-blue pieces, filled with the surrounding hair, and its leftover rim cleaned on every sprite |
| Body clean-up | Sock tops cleaned of leg-skin flecks; see-through pockets in clothing sealed; islands under 60 px dropped; fabric-class blobs inside the head become bangs (20); solid-black pools below the face lifted one ramp step (06's bow); 12's shoulder strands recoloured as hair |
| 21 | Steel kitchen knife (the drawing's blade re-read as polished steel with a lit edge) |
| 29 | Coded glitch: slice displacement, crimson/ice ghost split, scanlines, dead blocks |
| 30 | The source's pink aura is removed only outside her outline (her face shadow stays); the right leg and right sleeve, lost against the white background, are the left ones mirrored, and its aura-lit hands are 26's claws (same pose); coded blood aura with flame tongues and drips |
| Rebuild | `ls [0-3][0-9]_*.jpg [0-3][0-9]_*.png \| xargs -n 4 env LEILA_SCALE=2 python3 tools/art/leila_px.py . <tmp>` then `python3 tools/art/leila_hd.py <tmp> art/leila` |

Still optional for later: blink frames (eyes-closed variants of each face are trivial now, since faces are data)
and talking mouth frames. The full feeling → sprite → sound mapping lives in **docs/10_CASTING.md**.
