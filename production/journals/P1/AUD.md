# AUD journal — P1

## P1.12 — AudioDirector v1 (2026-11-03)
- Built `game/autoload/AudioDirector.gd`: bus tree from data (MusicA/MusicB = hidden
  crossfade pair under Music), music state machine with injected-clock hold/crossfade,
  cue pipeline with token-bucket budget, repeat window, rare caps, silence rule.
- Convention chosen: all docs/02 §2/§5 audio tables live in `game/data/audio_rules.json`
  (gates re-checked inside the director even though P1.07 gates the schema — never trust
  the model). Cue budget = token bucket, first turn starts at cap.
- New tool `tools/audio/import_audio.py`: ffmpeg loudnorm + silence-trim + .ogg, writes
  deterministic `.import` files (uid/md5 scheme borrowed from the sprite bridge, music
  gets loop=true). `--max-stage N` selects gate-wise; `--check` verifies committed outputs.
- Gotchas: `ResourceLoader.load_threaded_request` works headless; `AudioServer` fully works
  with the Dummy driver (buses, volumes, mutes — only `playing` never advances position).
  gdformat collapses `minf(` calls onto one line — run it before committing, not after.
  `_resolve_src` must stay in lockstep with `sanitise_relpath` in Python (parity test guards it).
- Over-early music requests queue (pending_music) rather than drop — deviation noted in handoff.
- Import scope for v1: stage-0 cues + stage-0/1 music bands + voice_blip.stage0_2 = 24 files.
  Re-run with bigger --max-stage as later stages open; P2.16 adds stage DSP + wrong-voice.
