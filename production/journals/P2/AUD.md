# AUD — P2 journal (Audio Engineer)

## Round 1 (2026-11-04, agent: commandcode)
- P2.16: AudioDirector now owns the stage layers. Music states resolve to the docs/04 §8.3
  stage bands (`_band_files`), the Music bus runs the §2 drift (pitch −5 cents/stage, low-pass
  12 kHz→9 kHz after stage 2, distortion/reverb by stage; `audio_rules.json` `stage_layers`),
  and `text_blip()` voices her text from `casting.json` `voice_by_stage` (AWAKE ≥ 3, stage 5
  demon 30% under stage-4 whispers, feeling pitch/gain, `empty` = silence).
- Gate tables are asserted against docs/02 §2.1/§2.2 (`AudioStageLayersTest.gd`); the cue
  silence rule is measured at ~10% over 2000 seeded turns at stage 3 and 0 below stage 3.
- Imported every music band (stages 0–5, 23 tracks) plus all five blip pools; added
  `import_audio.py --music-stage` so the music scope opens without pulling high-stage cue assets.
- Gotcha: the importer's −40 dB silence trim swallowed 4 short voice blips into header-only
  OGGs (incl. P1.12's female_light_3). Trim now applies to `sfx` only — always run
  `ffmpeg -v error -i <ogg> -f null -` after an import.
- Gotcha: `game/data/cue_map.json` is generated; run `tools/bridge/export_to_godot.py` after
  editing `assets/audio/cue_map.json` or the game keeps the stale map.
- Lint: AudioDirector sits exactly at gdlint's 20-public-method cap (`get_stage()` was removed to
  make room for `text_blip()`); new test surfaces must split at 20 methods, not raise the cap.
