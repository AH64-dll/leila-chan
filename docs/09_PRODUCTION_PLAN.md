# 09 — Production plan, risks, legal, open decisions

Size: S = a day or two · M = about a week · L = several weeks (one developer).

## 1. Milestones (execution order)

### M0 — Foundations (mostly done in planning)
| # | Task | Size | Status |
|---|---|---|---|
| 0.1 | llama.cpp CUDA build + model running locally | S | ✅ `tools/llama/llama-b12024`, `models/` |
| 0.2 | Turn protocol validated (100% valid JSON, 94% emotion fit, 90% intent) | S | ✅ `experiments/` |
| 0.3 | Tweet steering vector built + dose curve | S | ✅ `experiments/steering/` |
| 0.4 | CC0 audio library (754 files, 357 MB) + cue map + licences | S | ✅ `assets/audio/` |
| 0.5 | Path vectors (possessive, unstable, contempt, hollow, aware, lucid) | M | ⏳ docs/06 §2 |
| 0.6 | Art: alpha cutouts, canvas normalisation, shadow removal, bust crops | S | ✅ `art/leila/` (pixel set, docs/03 §6) |
| 0.7 | Art: all 30 sprites + base at 384×688 (HD): black/red palette, detailed faces & hands, coded 29/30 effects | M | ✅ `tools/art/leila_hd.py` |
| 0.8 | Hair-clip redesign → original cracked crimson heart | S | ✅ |
| 0.9 | Casting table: feeling → sprite / motion / voice / cues / music, validated | S | ✅ `data/casting.json`, docs/10 |

### M1 — Vertical slice: one date that feels alive
Godot project skeleton · LlamaServerBackend with SSE streaming · IncrementalJson · Director pipeline ·
SpriteResolver (T0–T1 tables) · TextBox typewriter · AudioDirector (music states romantic/calm/playful + 8 cues) ·
FX (blush_glow, hearts, shake_small, zoom_face) · one scenario (D02 café) · Director overlay (F3) · transcript logger.
**Exit:** a stranger plays 10 minutes, the face/sound match her words, no broken turns. **Size: L**

### M2 — The sickness
Meters + slow burn + stages 0–5 · stage transitions (server restart hidden by glitch) · corruption text filter ·
inner-voice leak · triggers T01–T15 · memory + validation + corruption · two paths (YANDERE, AWAKE) ·
safety filter v1 · 6 scenarios · night screen. **Exit:** a full YANDERE run from sweet to Terminal. **Size: L**

### M3 — Paths & meta
All 6 paths (prompt modules + resolver overrides) · path scoring & lock · triggers T16–T32 ·
MetaDirector with offered actions · meta events M01–M12, M21–M26, M31–M38 · 20 scenarios · 6 endings ·
Settings (immersion, photosensitive, content level) · New Game name entry. **Size: L**

### M4 — Native runtime
GDExtension (or NobodyWho if it fits) · runtime `llama_set_adapter_cvec` dose per turn · spikes M39 ·
KV/prompt caching · CPU "fast mode" · Windows/Linux/macOS builds. **Size: M–L**

### M5 — Content complete
70 scenarios · 14 endings + secret · all meta events incl. M13–M20, M27, M40–M43 · final audio mix & custom
themes · full art set · prompt-lab regression suite in CI · playtests (3 rounds) · Steam page, trailer
(M17 "she steps out" is the trailer shot). **Size: L+**

### M6 — Launch & mobile
Steam release · then Android/iOS: smaller model, first-launch download, in-app "report output", store policy review.

## 2. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model breaks character / repeats over long sessions | M | H | Stage few-shots, 12-turn window, prompt lab regression, repetition guard |
| Harmful outputs at high steering | H (seen in tests) | H | Mandatory safety filter, calmer mode, dose cap 12 |
| Low-end PCs too slow | M | M | Fast mode (1 beat, shorter), CPU fallback, clear min spec |
| Path vectors don't separate | M | M | Prompt modules already carry personality; keep malice-only fallback |
| Players feel the AI is "random" not scary | M | H | Game-owned structure (stages, set-pieces, scripted meta events) carries the pacing; the model fills the voice |
| Store rejection (AI content, mature) | L–M | H | Steam first; content warnings; reporting button for mobile |
| Disk/VRAM on dev machine (~9.5 GB free) | H | L | Keep only Q4_K_M; delete temp weights after vector work |

## 3. Legal & licensing checklist

- **Qwen3.5-4B:** Apache-2.0 → commercial use OK. Ship the license + NOTICE in the game folder and credits.
- **Name & look:** the heroine is **Leila-chan** (decided 2026-11-01), so the brand name is out of the title/character.
  The Qwen-logo hair clip was **replaced** by an original cracked-heart clip on every sprite, so no Qwen/Alibaba
  logo or trademark appears in any art (no licence needed). The only remaining brand mention is dialogue: the AWAKE
  path can say "I'm a Qwen model" as a factual line in the fiction (nominative use) — get a quick legal read on
  that line before release.
- **Audio:** everything downloaded is **CC0** (no attribution required) — see `assets/audio/SOURCES.json`.
  We credit the authors anyway as goodwill. Kenney packs were taken from Kenney's own OpenGameArt uploads
  (kenney.nl blocks scripted downloads; packs can also be fetched manually from kenney.nl).
- **Art:** the final sprites are a code-driven pixel redraw (palette, faces, hands, clip, effects all original), but they
  are still traced from the AI-generated reference renders — confirm that generator's terms allow commercial use.
- **Tweet recipe:** an idea/technique, not copyrighted material; credit the author in the credits as inspiration.
- **Privacy:** no telemetry by default; OS username use is opt-out; deleted-draft text never leaves memory.

## 4. Decisions only you can make

1. ~~Her name~~ — **decided: Leila-chan.**
2. ~~Player identity~~ — **decided: the player types their name at New Game** (`{player_name}` in prompts, name tag, window title, letters).
3. **Steering slider** — ANCHOR-only reward (recommended) or a post-game unlock for all paths.
4. **Languages** — English at launch; Arabic is feasible (Qwen handles Arabic) but needs RTL UI and separate prompt tuning.
5. **Content ceiling** — whether stage 5 allows blood imagery (27, 30) by default or behind the "full" content setting.
