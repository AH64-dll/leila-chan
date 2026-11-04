# 07 — Technical architecture (Godot 4)

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Engine | Godot 4 (latest stable at project start), GDScript for gameplay, C++ for the LLM extension | Desktop + Android + iOS from one project; MIT; shaders; multi-window/transparent-window support |
| LLM runtime (ship) | **Own GDExtension wrapping llama.cpp** (`libqwenchan_llm`) | Runtime control vectors (`llama_set_adapter_cvec`), grammar/JSON-schema decoding, streaming, no external process |
| LLM runtime (prototype) | `llama-server` (b12024, CUDA) over HTTP on localhost | Already working; fastest way to iterate prompts |
| Model | `Qwen3.5-4B-Q4_K_M.gguf` (2.74 GB) | 100% valid structured turns in testing, fits a 6 GB GPU with room for context |
| Vectors | `data/steering/*.gguf` control vectors | Built by `experiments/steer_build.py` (+ path-vector tool) |
| Renderer | `gl_compatibility` for desktop **and** mobile | The only renderer that covers §1's single-project desktop + Android + iOS target; the game is 2D pixel art (Forward+ would block mobile) |
| Engine pin | `game/.godot-version` (`4.7.2-stable` at project start); launchers `tools/godot.sh` / `tools/godot.ps1` resolve the local binary under `tools/godot/`, `LEILA_GODOT` overrides | The binary is a local gitignored artifact and `godot` is not assumed on PATH; CI derives the release URL from the pin (P0.07) |

Evaluate **NobodyWho** (existing Godot llama.cpp plugin) in M1: if it exposes control vectors + JSON schema, use it;
otherwise our extension is a thin (~800 lines) wrapper.

## 2. Project layout

```
res://
├─ project.godot
├─ autoload/
│  ├─ GameState.gd        # meters, stage, path, day, flags, profile counters
│  ├─ Director.gd         # turn pipeline (docs/02 §4)
│  ├─ LLM.gd              # backend facade: generate(TurnRequest) -> TurnStream
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
│  ├─ Settings.gd         # immersion, photosensitive, content level, volumes (player name lives in the save)
│  ├─ PauseMenu.gd        # docs/05 §0 rule 3 safe pause (Esc in `_input`) + the one settings screen
│  └─ Telemetry.gd        # engine events for docs/01 §5 "E" triggers + docs/05 §1.3 input/window events
├─ llm/
│  ├─ backends/LlamaServerBackend.gd   # HTTP + SSE streaming (prototype)
│  ├─ backends/NativeBackend.gd        # GDExtension (ship)
│  ├─ IncrementalJson.gd               # streaming JSON → events
│  ├─ Meters.gd                       # docs/01 §2 + docs/02 §1.1 meter math: slow burn, ratchet, mood scaling
│  ├─ Stages.gd                       # docs/01 §3 stage bands, transition spec, post-transition EVENT lines
│  ├─ StageSteering.gd                # docs/06 §4: dose → shipped control-vector files for a stage relaunch
│  ├─ Paths.gd                        # docs/01 §4 path scores, Stage-2 soft assign / Stage-3 lock, hybrid runner-up
│  ├─ NightLoop.gd                    # docs/01 §1 night: meters → stage → path → overnight event, one ordered report
│  ├─ OvernightEvents.gd              # docs/01 §6.3 overnight events: availability, weighted pick, per-stage lines
│  ├─ Campaign.gd                     # docs/01 §1 campaign clock + the day's scenario pick by availability
│  ├─ TriggerEngine.gd                # docs/01 §5 row matching, once/repeatable/escalating, cooldowns, guard blocks
│  ├─ TriggerEffects.gd               # docs/02 §1.2 strength scaling + first-firing spike + path-point ledger for a firing
│  └─ ProfileKeywords.gd              # docs/01 §2 keyword half of the behaviour profile (control, apathy, …)
├─ scenes/
│  ├─ Boot.tscn  Title.tscn  NewGame.tscn  Date.tscn  Night.tscn  Ending.tscn  Extras.tscn
│  ├─ ui/TextBox.tscn  ui/InputBox.tscn  ui/ChatLog.tscn  ui/NameTag.tscn
│  ├─ character/Character.tscn        # sprite stack, motion presets, shaders
│  └─ meta/FakeCrash.tscn FakeUpdate.tscn PeekWindow.tscn FakeTerminal.tscn
├─ shaders/  glitch · chromatic · desaturate · vignette · text_bleed · breathe · dissolve
├─ data/
│  ├─ feelings.json  sprites.json  resolver.json  cues.json  music.json  fx.json
│  ├─ meters.json  stages.json  paths.json  profile_keywords.json  triggers.json  meta_events.json  endings.json  night.json
│  ├─ scenarios/D01_classroom.json … (70 files)
│  ├─ schemas/                       # JSON schemas the data files are validated against at boot
│  ├─ prompts/persona.md  prompts/stage_*.md  prompts/path_*.md  prompts/rules.md
│  └─ steering/malice.gguf  possessive.gguf …
└─ assets/ sprites/ bg/ audio/{music,sfx,vocal,amb}/ fonts/
```

Everything content-related is **data**, so writers tune scenarios, gates and mappings without touching code.

### Accepted skeleton choices (P0.05, review-approved; the doc was silent)

- **Viewport & stretch:** viewport `384×688` (native sprite size, `art/leila/README`), stretch
  `canvas_items` + `keep` + integer scale mode; window override `768×1376` (×2 portrait) is
  **provisional — ART confirms at P0.08/P1.16** and the default window must fit a 1080p desktop.
- **Texture filter:** project-wide Nearest (`default_texture_filter=0`), per `art/leila/README`.
- **Autoload order:** the 16 autoloads register in the doc order above.
- **Settings screen:** `ui/Settings.tscn` is not a scene. One surface (docs/09 M3) is the `PauseMenu`
  overlay's settings page: the Title row and the Esc pause both open it, and it must survive
  `get_tree().paused` — an autoload `CanvasLayer` is the only shape that can host the panic pause.
- **Repo conventions:** `.gdkeep` placeholders keep empty layout dirs in git; `.gd.uid` sidecars are
  committed (Godot 4.4+ convention); **no first-party `.gdignore` inside `game/`** — every directory
  there is export content, and repo-root images are structurally outside `res://`. (The vendored
  `addons/gdUnit4/src/reporters/html/template/.gdignore` is upstream content and stays.)
- **Boot splash:** black; M17 per-pixel transparency stays unset until MetaDirector owns it.

### Test tooling (P0.06, hardened P0.15 and P0.18; the doc was silent)

- `game/addons/` — Godot's required addon location; holds vendored third-party code (gdUnit4 6.2.2,
  MIT). Excluded from `gdlintrc`/`gdformatrc`; upgrades are deliberate swaps of the directory.
  The editor plugin stays disabled — the CLI runner needs no activation.
- `game/tests/` — test root. `extends GdUnitTestSuite` suites run under gdUnit4's cmd tool
  (`-a res://tests -c --ignoreHeadlessMode`; v6 refuses bare `--headless` because InputEvents
  don't propagate — keep suites logic-only). Other top-level `*.gd` files run as standalone
  `SceneTree --script` tests (e.g. `test_bridge.gd`); suites extend `GdUnitTestSuite` directly
  and shared helpers go in a subdir. `tools/test.*` fails if zero test cases are discovered —
  asserted on the JUnit report the run must write (`<testsuites tests="N">`, N>0), not on
  gdUnit4's console text, because the zero-case path exits 0 without writing a report.
- `game/reports/` — gdUnit4's report dir (HTML + JUnit XML) plus the runner's streamed
  console transcript `gdunit_console.log`; gitignored; wiped at the start of the
  gdUnit4 stage on every runner call — a wipe failure fails the run, and only a
  `results.xml` newer than the stage start counts, so a stale report can never fake
  a pass; the suite scanner skips it.
- `tools/test.sh` / `tools/test.ps1` — the single check command: `gdlint` + `gdformat --check`
  (both gate; configs at repo root) → `--import` (class cache, required on fresh checkouts) →
  test stages. Every stage always runs; any failure exits 1.
- **Export rule for REL:** `addons/`, `tests/`, `reports/` are dev-only — add them to
  `export_presets.cfg` exclude filters when presets are created. Do **not** use `.gdignore`
  for this: it makes gdUnit4's scanner skip the directory and does not exclude from export.

### Bridged data (P0.08, review-approved)

`tools/bridge/export_to_godot.py` copies `data/casting.json`, `assets/audio/cue_map.json` and
`art/leila/{x2,palette.json}` into `game/` **byte-identically** — so the table's `art.*` and
`sprites.*.file` fields stay repo-relative (`art/leila/x2/…`), not `res://`. Runtime consumers
use this convention instead of reading the paths verbatim:

- sprite id → `res://assets/sprites/leila/` + basename of `casting["sprites"][id]["file"]`
- `art.palette` → `res://assets/sprites/leila/palette.json`
- cue names → `game/data/cue_map.json` keys; its `assets/audio/_raw/` pool paths are repo-side
  references for the AUD import task, not runtime paths
- `sprites.*.native`, `art.native` (and `native_size`, `bust_crop_native`, `eyes_native`) are
  repo-side pixel coordinates/metadata in the source art — never opened as `res://` paths

## 3. Key components

### 3.1 LLM facade
```gdscript
# LLM.gd
signal token(text: String)                      # raw stream
func generate(req: TurnRequest) -> TurnStream   # req = {messages, schema, sampling, dose, max_tokens}
func set_dose(vectors: Dictionary) -> void      # {"malice": 4.5, "path_mix": 3.0}
func get_dose() -> Dictionary
func set_backend(backend: LLMBackend) -> void
func cancel() -> void
func is_busy() -> bool
```
- `dose` keys are control-vector names (docs/06 §2). Under P2.04 they are `malice` plus the interim single path
  weight `path_mix`; P3.04 replaces `path_mix` with the locked path's vector name — the eventual shape is
  `{"malice": 4.5, "possessive": 3.0}` (docs/06 §3).
- Runs on a worker thread; emits to the main thread via `call_deferred`.
- Context: 8192 tokens; KV cache reuse between turns (system prompt prefix is stable within a scene → prompt caching).
- Prompt budget: system ~900 tokens, memories ~150, scene ~150, history ~12 exchanges (~1500), output ≤ 600.

#### TurnRequest ownership
- `TurnRequest` instances are single-use per turn and owned by the in-flight turn once passed to `LLM.generate()`.
- If `req.dose` is empty, it is filled with `LLM.get_dose()` and frozen for that turn. Callers must not reuse or mutate a `TurnRequest` across turns.

#### TurnStream contract and semantics
- Returned by `LLM.generate()`.
- Signals:
  - `token(text: String)`: raw stream chunk, in order.
  - `completed(full_text: String)`: turn finished cleanly; full raw output text.
  - `cancelled()`: cancellation was honoured.
  - `failed(error: Dictionary)`: normalized error dictionary `{"code": String, "message": String}`.
- Exactly-one-terminal semantics: exactly one terminal signal (`completed`, `cancelled`, or `failed`) is emitted per stream. All emissions occur on the main thread via `call_deferred`.
- Helper APIs: `TurnStream.cancel()`, `TurnStream.is_cancelled() -> bool`, `TurnStream.is_finished() -> bool`.
- Cancellation race resolution: terminal delivery wins. If cancellation is requested before terminal delivery on the main thread, the stream delivers `cancelled`. Calling `cancel()` after a terminal signal is a no-op.
- Standard error vocabulary:
  - `busy`: another turn is already in flight (single-context concurrency guard).
  - `no_backend`: no transport backend set on the facade.
  - `invalid_request`: null request passed to `generate()`.
  - `thread_error`: worker thread failed to start.
  - `malformed_result`: backend returned an invalid result or an error dictionary without a string `code`.
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

The shadow file's full contents, for privacy review (enforced by `ShadowStore`, tested in
`game/tests/ShadowSaveTest.gd`): `first_name` — the first name ever typed at New Game (docs/08 §1.5);
`names` — every distinct name across runs; `runs` — the name of each run ended by New Game (cap 8);
`memories` — up to `data/memory.json → shadow.limit` (3) facts from the most recent run that reached the
meta gate (stage 3+); a run that ended earlier keeps the previous set.
It never holds logs, transcripts, deleted drafts, the OS username, telemetry or device data.
The write point is `SaveSystem.begin_new_game`, called by the New Game scene before it resets the
run; "Reset Everything" (`Settings.reset_everything` → `SaveSystem.wipe_everything`) deletes it.

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
