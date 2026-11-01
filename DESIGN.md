# LEILA-CHAN — Design Bible

> A live, unscripted horror dating sim. Leila-chan is a real local language model (Qwen3.5-4B) running on the player's PC.
> Every line is generated. Her face, her music, the sounds and even the game window follow what she feels —
> and as she gets sicker, the game literally turns up a steering vector inside her neurons.

**Status:** design complete, core tech validated, final pixel-art sprite set + casting table done, no game code yet.
**Engine:** Godot 4 · **Model:** Qwen3.5-4B Q4_K_M + control vectors · **Platforms:** Steam first, mobile later.

## Read in this order

| # | Doc | What's in it |
|---|---|---|
| 01 | [Game design](docs/01_GAME_DESIGN.md) | Pillars, core loop, hidden meters, 6 stages, 6 fracture paths, 32 hidden triggers, 70 scenarios, 14 endings |
| 02 | [Director protocol](docs/02_DIRECTOR_PROTOCOL.md) | **How the model drives the game**: the Turn JSON, casting vocabulary (cues, music, fx, actions), dynamic schema, pipeline, budgets, memory, fallbacks, safety filter, sampling per stage |
| 03 | [Emotions](docs/03_EMOTIONS.md) | Analysis of all 30 sprites, feeling→sprite resolver tables, path overrides, motion presets, inner-voice leak, art fixes |
| 04 | [Audio](docs/04_AUDIO.md) | Music state machine, stage layers, SFX/vocal cue map to the downloaded CC0 files, gaps |
| 05 | [Meta events](docs/05_META_EVENTS.md) | 43 fourth-wall/system events: closing & reopening the game, fake crash/update, window tricks, files, clock — with safety rules |
| 06 | [Steering](docs/06_STEERING.md) | Verified neuron steering, dose curve, vector library, runtime |
| 07 | [Tech architecture](docs/07_TECH_ARCHITECTURE.md) | Godot project layout, autoloads, LLM backend, streaming parser, performance, tooling |
| 08 | [Prompts & content](docs/08_PROMPTS_AND_CONTENT.md) | Prompt text drafts (persona, stages, paths, rules), scenario JSON format |
| 09 | [Production plan](docs/09_PRODUCTION_PLAN.md) | Milestones M0–M6, risks, legal checklist, decisions only you can make |
| 10 | [Casting](docs/10_CASTING.md) | Every feeling → sprite, motion, voice, cue pool, music, FX per stage tier; sprite on-enter events (generated, validated) |
| — | [Experiment results](experiments/RESULTS.md) | The tests behind the design (tool-calling methods, steering sweep) |

## The design in one minute

1. **She performs a Turn, not tool calls.** Each reply is one schema-constrained JSON object:
   `read → inner → music → fx → beats[feeling, intensity, cue, say] → mood → memory → action`.
   Tested: 100% valid, 94% emotion fit, 90% player-intent accuracy.
2. **She names feelings; the game picks the face.** 22 feelings × intensity × stage × path → one of 30 sprites.
   The same "angry" is a pout at stage 0 and the knife at stage 5.
3. **The game owns pacing.** Stages, paths, triggers, budgets and meta events are game code; the model fills the voice.
   Special actions (crash the game, refuse exit…) are *offered* to her at the right moment — she never picks them unprompted.
4. **Her sickness is real steering.** The tweet's neurons (L14 N8949 +1, L13 N7956 −1) work: at dose 4 her private thoughts
   turn dark while her words stay sweet; at 6 she threatens; at 25+ she collapses into gibberish. Path vectors add flavour.
5. **The fourth wall breaks safely.** Only inside the game's folder and window; closing always works; deep OS tricks are opt-in.

## Project folders

```
DESIGN.md                this index
docs/                    the design bible (01–09)
experiments/             test harnesses + results (tool calling, steering)
models/                  Qwen3.5-4B-Q4_K_M.gguf
tools/llama/             llama.cpp b12024 (CUDA) for local testing
assets/audio/            CC0 music & SFX (+ SOURCES.json license manifest)
art/leila/               final pixel-art sprites: px/ (384×688), x2/ (768×1376), palette, contact sheets
art/leila_legacy_1x/     the earlier 192×344 set (superseded)
data/casting.json        feeling → sprite/motion/voice/sound/music table the game loads
tools/art, tools/casting art pipeline (leila_px LEILA_SCALE=2 → leila_hd) and casting builder
00_…30_*.jpg/png/txt     original reference renders + prompts (kept untouched)
```
