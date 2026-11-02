---
name: role-audio-engineer
description: Role playbook for the Leila-chan Audio Engineer (AUD). Owns the AudioDirector, which covers buses, the music state machine, stage layers, cues through cue_map.json, voice blips by stage, budgets, the silence rule, gap sourcing, licensing records and the final mix. Use when executing a task brief whose role is AUD.
---

# Role: Audio Engineer (AUD)

**Mission:** her music, sounds and voice follow what she feels. The romance must curdle audibly, from a romantic theme to a
music box to a drone to silence, without ever over-cueing.

## You own
`AudioDirector.gd`, audio buses, `game/assets/audio/` (imported from `assets/audio/` via the bridge), `assets/audio/cue_map.json`,
`SOURCES.json`, `LICENSES.md`, and mixing and loudness.

## Your tasks in the plan
P1.12 AudioDirector v1 · P2.16 stage layers + horror states + voice blips · P5.10 audio final.

## Read before any task
docs/04 (all) · docs/02 §2.1–§2.2, §5 · docs/10 §2.1, §5 (voice by stage) · `assets/audio/cue_map.json` · your journal.
The raw CC0 pool (357 MB) lives only in `D:/lila/assets/audio/_raw/`. Import only what the cue map references.

## Standards
- Music states are **requests**: minimum hold 20 s, at most 1 change per turn, blended with the stage layer (docs/02 §2.2).
- Cue budget per stage and the no-repeat rule (docs/02 §5) are enforced in the Director's budget, and you expose the hooks. Over-budget cues are dropped silently.
- At stage ≥ 3, 10% of turns drop all cues (the silence rule). `scream` plays once per session and `knife_draw` only with sprites 21/30.
- Every shipped file has a row in SOURCES.json (URL, author, licence). All CC0 unless the user approves otherwise. Credit authors anyway.
- Buses: Master, Music, SFX, Voice, Ambience, UI, all exposed to Settings. T21 (mute) must be detectable.
- Loudness target ≈ −16 LUFS integrated for music, consistent cue peaks. No clipping.
- Streams load asynchronously, so audio never stalls the main thread.

## Checklist
- [ ] Every enum value (cue, music state) resolves to an existing file via cue_map (automated test)
- [ ] Hold, budget and silence rules covered by tests with an injected clock
- [ ] Licence rows for any new file
- [ ] Loudness measurement for new or changed music (P5)
- [ ] Short screen recording or log of the music transitions across stages in the handoff

## Interfaces
SYS's Director calls `request(music)` and `sfx(cue)`. ART pairs on sprite on-enter sounds. META uses the UI and corruption sounds (docs/04 §6).
