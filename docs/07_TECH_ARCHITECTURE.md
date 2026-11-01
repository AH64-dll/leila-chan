# 07 — Technical architecture (Godot 4)

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Engine | Godot 4 (latest stable at project start), GDScript for gameplay, C++ for the LLM extension | Desktop + Android + iOS from one project; MIT; shaders; multi-window/transparent-window support |
| LLM runtime (ship) | **Own GDExtension wrapping llama.cpp** (`libqwenchan_llm`) | Runtime control vectors (`llama_set_adapter_cvec`), grammar/JSON-schema decoding, streaming, no external process |
| LLM runtime (prototype) | `llama-server` (b12024, CUDA) over HTTP on localhost | Already working; fastest way to iterate prompts |
| Model | `Qwen3.5-4B-Q4_K_M.gguf` (2.74 GB) | 100% valid structured turns in testing, fits a 6 GB GPU with room for context |
| Vectors | `data/steering/*.gguf` control vectors | Built by `experiments/steer_build.py` (+ path-vector tool) |

Evaluate **NobodyWho** (existing Godot llama.cpp plugin) in M1: if it exposes control vectors + JSON schema, use it;
otherwise our extension is a thin (~800 lines) wrapper.

## 2. Project layout

```
res://
├─ project.godot
├─ autoload/
│  ├─ GameState.gd        # meters, stage, path, day, flags, profile counters
│  ├─ Director.gd         # turn pipeline (docs/02 §4)
│  ├─ LLM.gd              # backend facade: generate(prompt, schema, sampling, dose) -> TurnStream
│  ├─ PromptBuilder.gd    # assembles layered prompt (docs/08)
│  ├─ SpriteResolver.gd   # feeling × intensity × stage × path → sprite (docs/03)
│  ├─ AudioDirector.gd    # music states, layers, SFX, budgets (docs/04)
│  ├─ FX.gd               # screen effects, shaders, camera
│  ├─ MetaDirector.gd     # meta/system events, offers, scheduling (docs/05)
│  ├─ Triggers.gd         # keyword/engine/clock triggers (docs/01 §5)
│  ├─ Memory.gd           # player facts, validation, corruption
│  ├─ Safety.gd           # output filter, redaction, content settings
│  ├─ Steering.gd         # dose schedule, vector mixing
│  ├─ SaveSystem.gd       # saves + shadow save + letters (user:// only)
│  └─ Settings.gd         # immersion, photosensitive, content level, volumes (player name lives in the save)
├─ llm/
│  ├─ backends/LlamaServerBackend.gd   # HTTP + SSE streaming (prototype)
│  ├─ backends/NativeBackend.gd        # GDExtension (ship)
│  └─ IncrementalJson.gd               # streaming JSON → events
├─ scenes/
│  ├─ Boot.tscn  Title.tscn  NewGame.tscn  Date.tscn  Night.tscn  Ending.tscn  Extras.tscn
│  ├─ ui/TextBox.tscn  ui/InputBox.tscn  ui/ChatLog.tscn  ui/NameTag.tscn  ui/Settings.tscn
│  ├─ character/Character.tscn        # sprite stack, motion presets, shaders
│  └─ meta/FakeCrash.tscn FakeUpdate.tscn PeekWindow.tscn FakeTerminal.tscn
├─ shaders/  glitch · chromatic · desaturate · vignette · text_bleed · breathe · dissolve
├─ data/
│  ├─ feelings.json  sprites.json  resolver.json  cues.json  music.json  fx.json
│  ├─ stages.json  paths.json  triggers.json  meta_events.json  endings.json
│  ├─ scenarios/D01_classroom.json … (70 files)
│  ├─ prompts/persona.md  prompts/stage_*.md  prompts/path_*.md  prompts/rules.md
│  └─ steering/malice.gguf  possessive.gguf …
└─ assets/ sprites/ bg/ audio/{music,sfx,vocal,amb}/ fonts/
```

Everything content-related is **data**, so writers tune scenarios, gates and mappings without touching code.

## 3. Key components

### 3.1 LLM facade
```gdscript
# LLM.gd
signal token(text)                 # raw stream
func generate(req: TurnRequest) -> TurnStream   # req = {messages, schema, sampling, dose, max_tokens}
func set_dose(vectors: Dictionary) # {"malice": 4.5, "possessive": 3.0}
```
- Runs on a worker thread; emits to the main thread via `call_deferred`.
- Context: 8192 tokens; KV cache reuse between turns (system prompt prefix is stable within a scene → prompt caching).
- Prompt budget: system ~900 tokens, memories ~150, scene ~150, history ~12 exchanges (~1500), output ≤ 600.

### 3.2 IncrementalJson
A tiny state machine over the token stream that emits: `field(name, value)` when a scalar field closes,
`beat_start(i)`, `beat_field(i, name, value)`, and `say_chunk(i, text)` for partial strings.
Because the schema fixes property order (`read, inner, music, fx, beats[feeling, intensity, cue, say], mood, memory, action`),
the parser knows what comes next — no lookahead needed.

### 3.3 Character
Sprite stack: `Shadow` · `Body` (current sprite, crossfade) · `Overlay` (blush/tears/blood decals, optional) ·
`FX` (shader material). Camera: `Camera2D` with presets `full`, `knees`, `bust`, `face`.

### 3.4 Text pipeline
`say chunk → Safety.scan → PronounFix → Corruption.filter(stage, path) → Typewriter`.
Corruption filter effects by stage: hesitation pauses (1+), strike-through self-corrections (2+),
word repetition / wrong name (3+), zalgo bursts & redaction (4+), text bleed & reverse lines (5).

### 3.5 Saves
`user://saves/slot_N.json` (state, memories, log), `user://.leila/shadow.json` (persists across New Game, docs/05 M08),
`user://letters/`, `user://diary/`. Settings → "Reset Everything" deletes all of `user://` except settings.

## 4. Threading and performance

| Item | Budget (RTX 4050 6 GB) |
|---|---|
| Model VRAM | ~3.0 GB weights + ~0.6 GB KV @ 8k ctx |
| Godot VRAM | < 800 MB (2D, compressed sprites) |
| First beat on screen | < 1.0 s (streamed) |
| Full turn | 2–3.5 s (measured 2.2–3.2 s) |
| CPU-only fallback | ~6–10 tok/s on a modern 8-core → offer "Fast mode" (shorter replies, 1 beat) |

Min spec (store page): 8 GB RAM + GPU with 4 GB VRAM (CUDA/Vulkan/Metal) or a fast CPU (slow mode).

## 5. Dev tooling (build alongside M1)

- **Director overlay (F3):** live meters, stage/path, current dose, last `read`, `inner`, cue budget, offered actions.
- **Transcript logger:** every turn's prompt, schema, raw output, applied events → `user://debug/` (dev builds only).
- **Replay:** re-run a saved transcript with a different dose/prompt to compare.
- **Prompt lab:** the Python harness in `experiments/` grows into a regression suite: ~100 scripted player
  messages per stage/path; CI fails if JSON validity < 99%, intent accuracy < 85%, emotion fit < 85%.

## 6. Build & distribution

- Desktop: Windows/Linux/macOS exports; llama.cpp built per platform (CUDA + Vulkan on Win/Linux, Metal on macOS).
  The model is a separate 2.7 GB file in the install folder (Steam depot), loaded at boot with a diegetic loading screen.
- Mobile (later): Android/iOS export, model downloaded on first launch (Play Asset Delivery / background download),
  smaller model option, vectors re-derived for it (docs/06 §5).
