# LEILA-CHAN — Design Bible & Asset Pipeline

> A live, unscripted **horror dating sim**. Leila-chan is a real local language model
> (Qwen3.5-4B) running on the player's PC. Every line is generated. Her face, her music,
> the sounds and even the game window follow what she feels — and as she gets sicker,
> the game literally turns up a steering vector inside her neurons.

**Status:** design complete, core tech validated, final pixel-art sprite set + casting
table done, **no game code yet**.
**Engine:** Godot 4 · **Model:** Qwen3.5-4B Q4_K_M + control vectors ·
**Platforms:** Steam first, mobile later.

## Start here

Read **[DESIGN.md](DESIGN.md)** — it is the index of the whole design bible:

| # | Doc | What's in it |
|---|---|---|
| 01 | [Game design](docs/01_GAME_DESIGN.md) | Pillars, core loop, hidden meters, 6 stages, 6 fracture paths, 32 hidden triggers, 70 scenarios, 14 endings |
| 02 | [Director protocol](docs/02_DIRECTOR_PROTOCOL.md) | **How the model drives the game**: the Turn JSON, casting vocabulary, dynamic schema, pipeline, budgets, memory, fallbacks, safety filter, sampling per stage |
| 03 | [Emotions](docs/03_EMOTIONS.md) | All 30 sprites analyzed, feeling→sprite resolver tables, path overrides, motion presets, inner-voice leak |
| 04 | [Audio](docs/04_AUDIO.md) | Music state machine, stage layers, SFX/vocal cue map, gaps |
| 05 | [Meta events](docs/05_META_EVENTS.md) | 43 fourth-wall/system events with safety rules |
| 06 | [Steering](docs/06_STEERING.md) | Verified neuron steering, dose curve, vector library, runtime |
| 07 | [Tech architecture](docs/07_TECH_ARCHITECTURE.md) | Godot project layout, autoloads, LLM backend, streaming parser, performance |
| 08 | [Prompts & content](docs/08_PROMPTS_AND_CONTENT.md) | Prompt drafts (persona, stages, paths, rules), scenario JSON format |
| 09 | [Production plan](docs/09_PRODUCTION_PLAN.md) | Milestones M0–M6, risks, legal checklist, open decisions |
| 10 | [Casting](docs/10_CASTING.md) | Every feeling → sprite, motion, voice, cue pool, music, FX per stage tier |
| — | [Experiment results](experiments/RESULTS.md) | The tests behind the design |

## The design in one minute

1. **She performs a Turn, not tool calls.** One schema-constrained JSON object per reply:
   `read → inner → music → fx → beats[feeling, intensity, cue, say] → mood → memory → action`.
   Tested: 100% valid, 94% emotion fit, 90% player-intent accuracy.
2. **She names feelings; the game picks the face.** 22 feelings × intensity × stage × path →
   one of 30 sprites. The same "angry" is a pout at stage 0 and the knife at stage 5.
3. **The game owns pacing.** Stages, paths, triggers, budgets, meta events are game code;
   the model fills the voice. Special actions are *offered* to her — never picked unprompted.
4. **Her sickness is real steering.** Neurons L14 N8949 +1, L13 N7956 −1: at dose 4 her
   private thoughts turn dark while her words stay sweet; at 6 she threatens; at 25+ gibberish.
5. **The fourth wall breaks safely.** Only inside the game's folder and window; closing
   always works; deep OS tricks are opt-in.

## Repo layout

```
DESIGN.md                 design bible index (start here)
docs/                     the design bible (01–10)
data/casting.json         feeling → sprite/motion/voice/sound/music table the game loads
art/leila/                FINAL pixel-art sprites: px/ (384×688), x2/ (768×1376), palette,
                          contact sheets — built by tools/art (see "Rebuilding the sprites")
tools/art/                sprite pipeline (leila_px → leila_hd, faces/hands/fix passes)
tools/casting/            casting.json builder
experiments/              test harnesses + results (tool calling, steering sweep)
assets/audio/             cue_map.json + SOURCES.json + LICENSES.md (raw CC0 audio excluded)
raw_references/           reference renders used to derive the character design
png_sprites/              generated full-res sprite set (pre-pixel-art pass)
00_…30_*.jpg/.png/.txt    original reference renders + their prompts (canonical, untouched)
```

## Local artifacts (not in this repo — too large)

These are intentionally gitignored; grab them once per machine:

| Path | What | How to get it |
|---|---|---|
| `models/Qwen3.5-4B-Q4_K_M.gguf` | The LLM weights (2.6 GB) | `huggingface-cli download <qwen3.5-4b-gguf-repo> Qwen3.5-4B-Q4_K_M.gguf --local-dir models` |
| `tools/llama/llama-b12024/` | llama.cpp b12024 binaries (CUDA) | GitHub release `ggml-org/llama.cpp` b12024 → Linux: `llama-b12024-bin-ubuntu-cuda-12.8-x64.tar.gz` + `cudart-llama-b12024-bin-ubuntu-cuda-12.8-x64.tar.gz` (or both `cuda-13.4`); Windows: `llama-b12024-bin-win-cuda-12.4-x64.zip` + `cudart-llama-bin-win-cuda-12.4-x64.zip` (or both `cuda-13.4`), each pair extracted into the same folder (or build from source). Override the path with `LEILA_LLAMA_BIN` / `LEILA_MODEL` or `--bin` / `--model` in `experiments/steer_sweep.py` |
| `assets/audio/_raw/` | Raw CC0 music/SFX pool (357 MB) | Re-download from the URLs in `assets/audio/SOURCES.json` |
| `art/leila_legacy_1x/` | Superseded 192×344 sprite set | Regenerate: `LEILA_SCALE=1` pipeline, or ignore (superseded) |

## Rebuilding the sprites

Dependencies (pinned, Python 3.12): `pip install -r requirements.txt` (sprite pipeline + casting),
`pip install -r requirements-experiments.txt` (`experiments/steer_build.py`).

One command, any OS (px → hd → casting; `--out DIR` builds elsewhere and skips casting):

```bash
python tools/art/build_all.py
```

Or step by step. `leila_px.py <src_dir> <out_dir> <names...>` needs `LEILA_SCALE=2` (it defaults to 4, the old
192×344 set) and file names **with** the extension; it writes `<name>.png` + `<name>.cls.npy` intermediates
(not in the repo). `leila_hd.py <px_dir> <out_dir>` then writes `px/`, `x2/`, the palette and contact sheets.

```bash
# bash
export LEILA_SCALE=2
python tools/art/leila_px.py png_sprites /tmp/leila_px $(cd png_sprites && ls *.png)
python tools/art/leila_hd.py /tmp/leila_px art/leila      # heart clip, per-sprite FIX passes, FX
python tools/casting/build_casting.py                     # → data/casting.json + docs/10 tables
```

```powershell
# Windows PowerShell
$env:LEILA_SCALE = "2"
$px = Join-Path $env:TEMP "leila_px"
python tools/art/leila_px.py png_sprites $px (Get-ChildItem png_sprites -Filter *.png).Name
python tools/art/leila_hd.py $px art/leila
python tools/casting/build_casting.py
```

**Determinism:** with the pinned versions the build is repeatable — same inputs, same pixels on the same
machine. It does **not** reproduce the committed `art/leila/` byte-for-byte: on Windows, every tested combination
(opencv-python-headless 4.9–4.14, numpy 1.26–2.5, scipy 1.13–1.18) gives the same output, which matches only
`00_base_reference`; the other sprites differ in scattered edge/line pixels, and `30_predatory_bloodlust` comes out
broken (its hard-coded FIX coordinates in `leila_hd.py` no longer line up). The committed set was apparently
built on Linux; the exact environment wasn't recorded. Treat `art/leila/` as the source of truth and check a rebuild by eye
(especially 30) before committing it.

## License / rights

- Game design, docs, code pipeline, generated pixel art: © the project authors (private repo — ask before reusing).
- `assets/audio/`: all CC0, per-file provenance in `SOURCES.json` / `LICENSES.md`.
- Model weights: subject to Qwen's model license; not distributed here.
