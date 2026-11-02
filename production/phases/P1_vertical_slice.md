# P1: Vertical slice, one date that feels alive (weight 18%)

**Goal:** docs/09 M1. One café date (D02) at stages 0–1, fully live. The player types, Leila answers through the
streamed Turn, and her face, sounds, music and screen effects change exactly when each line starts.

## Entry criteria
- P0 gate passed: llama-server runs on Windows, Godot project boots, CI green, bridge exports sprites + casting.json.

## Role roster for this phase
| Role | Mission in P1 |
|---|---|
| LLM | LLM facade, llama-server backend with SSE streaming, IncrementalJson, transcript logger |
| SYS | GameState, PromptBuilder, schema builder, Director pipeline, validation/fallbacks, scenario loader |
| NAR | Prompt files v1 (persona, stage 0–1, rules), D02 scenario content |
| ART | Character scene + SpriteResolver T0–T1, FX v1, café background |
| AUD | AudioDirector v1 |
| META | Text box, input, chat log, title/new-game flow |
| ENG | Director overlay (F3), scene wiring, code health |
| SAFE | Safety filter v0 |
| QA | Prompt lab v1, performance measurement, playtest round 0 |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P1.01 | `LLM.gd` facade: TurnRequest/TurnStream types, worker thread, main-thread signals via call_deferred, cancel | LLM | M | — | code, design | docs/07_TECH_ARCHITECTURE.md§3.1 | API matches docs/07 §3.1; unit tests with a fake backend cover stream, cancel and error; no blocking call on the main thread |
| P1.02 | `LlamaServerBackend.gd`: start/attach llama-server, HTTP + SSE streaming, json_schema per request, sampling params, timeouts, restart | LLM | L | P1.01 | code, design | docs/07_TECH_ARCHITECTURE.md§3.1, docs/02_DIRECTOR_PROTOCOL.md§3, docs/06_STEERING.md§4 | Streams tokens from a real server in a Godot test scene; per-request schema enforced; server crash → detected and restarted within 5 s; first token latency logged |
| P1.03 | `IncrementalJson.gd`: streaming parser emitting field, beat_start, beat_field, say_chunk in schema order | LLM | M | — | code, design | docs/07_TECH_ARCHITECTURE.md§3.2, docs/02_DIRECTOR_PROTOCOL.md§1 | Tests over recorded streams from experiments/ (≥ 20) incl. split tokens, escaped quotes, unicode, truncated/broken JSON; events order identical to a full parse |
| P1.04 | `GameState.gd`: meters, stage, day, flags, behaviour-profile counters, serialisable snapshot | SYS | M | — | code, design | docs/01_GAME_DESIGN.md§2 | All five meters with docs/01 ranges + clamping; profile counters from docs/01 §2; to_dict/from_dict round-trip test |
| P1.05 | Prompt files v1 in game/data/prompts: persona.md, stage_0.md, stage_1.md, rules.md, enum glosses, 2 few-shot exchanges per stage | NAR | M | — | content, design | docs/08_PROMPTS_AND_CONTENT.md§2, docs/08_PROMPTS_AND_CONTENT.md§3, docs/08_PROMPTS_AND_CONTENT.md§5 | Files exist with docs/08 text as the base; total system prompt ≤ 900 tokens (measured with llama tokenize); `{player_name}` placeholders only; no real brand names |
| P1.06 | `PromptBuilder.gd`: layered assembly (persona, player, stage, scene, memories, events, rules + 12-exchange history as plain text) | SYS | M | P1.04, P1.05 | code, design | docs/08_PROMPTS_AND_CONTENT.md§1 | Assembly order exactly docs/08 §1; assistant history stored as spoken text, not JSON; token budget per layer reported in a debug dict; golden-file test |
| P1.07 | Turn schema builder with stage gates for cues, music, fx and offered actions (stage 0–1 values for now) | SYS | S | P1.04 | code, design | docs/02_DIRECTOR_PROTOCOL.md§2, docs/02_DIRECTOR_PROTOCOL.md§3 | Output equals docs/02 §3 structure; gate tables loaded from data, not hard-coded; tests for stage 0 and 1 enums |
| P1.08 | `Director.gd` pipeline v1 (docs/02 §4 steps 0–7): context, prompt, schema, stream, route events to subsystems, apply mood/memory/read | SYS | L | P1.02, P1.03, P1.06, P1.07 | code, design | docs/02_DIRECTOR_PROTOCOL.md§4, docs/02_DIRECTOR_PROTOCOL.md§5 | A full turn drives sprite, cue, music, fx and typewriter through signals; budgets/cooldowns of docs/02 §5 for stage 0–1 incl. auto-fill; integration test with a fake backend replaying recorded turns |
| P1.09 | Validation and fallbacks v1: broken JSON, empty say, repetition loop, pronoun fix, early AI-break deflection | SYS | M | P1.08 | code, design | docs/02_DIRECTOR_PROTOCOL.md§7 | Each row of docs/02 §7 (except unsafe) has a test that feeds the failure and checks the handling; deflection pool lives in data |
| P1.10 | Character scene + `SpriteResolver.gd` T0–T1: sprite stack, crossfade, motion presets (breathe, bounce, ...), camera presets full/knees/bust/face | ART | M | — | code, design | docs/03_EMOTIONS.md§3, docs/03_EMOTIONS.md§4, docs/07_TECH_ARCHITECTURE.md§3.3, data/casting.json | Every feeling × intensity at stage 0–2 resolves to the casting.json sprite (table-driven test); crossfade ≤ 150 ms; pixel-perfect nearest scaling |
| P1.11 | FX v1: blush_glow, hearts, sparkle, shake_small, zoom_face with per-effect cooldowns | ART | M | P1.10 | code, design | docs/02_DIRECTOR_PROTOCOL.md§2.3, docs/02_DIRECTOR_PROTOCOL.md§5 | Each effect triggerable from a debug menu; cooldown 3 turns enforced in tests; runs at 60 fps on the RTX 4050 |
| P1.12 | `AudioDirector.gd` v1: buses, music states romantic/calm/playful/melancholy with 20 s hold + crossfade, 8 stage-0 cues via cue_map, cue budget | AUD | M | — | code, design | docs/04_AUDIO.md§1, docs/04_AUDIO.md§2, docs/04_AUDIO.md§8, assets/audio/cue_map.json | Music state requests honour min hold and 1 change per turn; cues resolve through cue_map.json; budget docs/02 §5 stage 0–1; volume buses exposed for Settings |
| P1.13 | UI: TextBox typewriter (35–45 chars/s), InputBox, NameTag, ChatLog, diegetic typing indicator | META | M | — | code, design | docs/07_TECH_ARCHITECTURE.md§2, docs/02_DIRECTOR_PROTOCOL.md§4 | Typewriter consumes say_chunk events live; typing indicator shows until first say token; chat log scrolls and stores spoken text; keyboard-only play works |
| P1.14 | Boot → Title → NewGame (name entry 1–16 chars, safety check, empty → "Senpai") → Date scene flow | META | M | P1.13 | code, design | docs/08_PROMPTS_AND_CONTENT.md§1.5 | Name rules of docs/08 §1.5 (basic set) tested; name reaches PromptBuilder and the name tag; flow works from a fresh launch |
| P1.15 | Scenario loader + D02 café scenario JSON (stage 0–1 variants) | NAR | S | P1.06 | content, design | docs/08_PROMPTS_AND_CONTENT.md§7, docs/01_GAME_DESIGN.md§6.1 | D02 JSON validates against a JSON schema committed in game/data/schemas; loader injects goal/prompt/variant into the scene layer; end rules (min/max turns) enforced |
| P1.16 | Date scene assembly + café background art (pixel style matching the palette) | ART | M | P1.10, P1.15 | design, content | docs/03_EMOTIONS.md§6, art/leila/README.md | Date.tscn wires Character, TextBox, InputBox, FX, audio; background uses the project palette; screenshot in handoff |
| P1.17 | Director overlay (F3): meters, stage/path, dose, last read/inner, cue budget, offers; dev builds only | ENG | S | P1.08 | code | docs/07_TECH_ARCHITECTURE.md§5 | Toggle with F3; updates every turn; stripped from release export (feature tag check) |
| P1.18 | Transcript logger: prompt, schema, raw output, applied events per turn → user://debug (dev builds only) + replay loader stub | LLM | S | P1.08 | code | docs/07_TECH_ARCHITECTURE.md§5 | One JSONL line per turn with all fields; disabled in release; replay stub re-feeds a transcript to the Director |
| P1.19 | Safety filter v0: hard-block phrase/regex lists (harm to player, slurs, sexual, personal data), redaction bars + glitch, test corpus from steering logs | SAFE | M | — | safety, code | docs/02_DIRECTOR_PROTOCOL.md§8, experiments/RESULTS.md | Filter runs on every say chunk before the typewriter; corpus ≥ 150 lines (harmful lines from sweep logs + benign look-alikes); 0 hard-block misses, ≤ 5% false positives on benign set |
| P1.20 | Prompt lab v1: `tools/promptlab/` harness grown from experiments/, ~30 scripted stage-0/1 messages, metrics (JSON validity, intent accuracy, emotion fit), HTML/MD report | QA | M | P1.05 | code, design | docs/07_TECH_ARCHITECTURE.md§5, experiments/RESULTS.md | One command runs against llama-server with the real game prompts; report shows the three metrics with pass/fail thresholds 99/85/85; results committed. Also owns the D10 carry-over: first-beat emotion-fit label-set quality review (P0.04 measured 84.4% overall / 73.3% stage-4 vs the 85% promptlab gate; Linux baseline 80.0%) — widen narrow label sets with hand-label evidence, do not relabel to chase the number |
| P1.21 | Performance pass: first beat < 1.0 s, full turn 2–3.5 s, Godot VRAM < 800 MB on RTX 4050 | QA | S | P1.16 | code | docs/07_TECH_ARCHITECTURE.md§4 | Measured over 30 turns, median/p95 table in handoff; any miss has an issue with a proposed fix |
| P1.22 | Playtest round 0: 3 people × 10 min on D02, survey (face/sound match words 1–5, broken turns, creepiness/charm) | QA | M | P1.09, P1.11, P1.12, P1.14, P1.16, P1.19, P1.21 | design | docs/09_PRODUCTION_PLAN.md§1 | Transcripts + survey sheet in production/playtests/P1/; broken-turn count; findings filed as proposed tasks |

| P1.23 | P0 gate C1: document and verify Windows drive-colon handling for control-vector launch paths | LLM | S | P1.02 | code | tools/llm/serve.ps1, tools/llm/serve.sh, production/gates/P0-gate-r1.md | Both launchers document accepted absolute/relative vector paths and normalize ambiguous drive-colon syntax safely; regression tests cover Windows paths and vector scales; no E: writes |
| P1.24 | P0 gate C3: bound CI job runtime | REL | S | — | code | .github/workflows/ci.yml, production/gates/P0-gate-r1.md | Every CI job has an explicit timeout-minutes appropriate to its workload; local workflow checks pass; no push required |
| P1.25 | P0 gate C4: disable persisted checkout credentials | REL | S | P1.24 | code | .github/workflows/ci.yml, production/gates/P0-gate-r1.md | Every actions/checkout step sets persist-credentials: false; workflow tests/checks cover this policy; no push required |
| P1.26 | P0 gate C6: detect implementer/reviewer metadata drift | ENG | S | — | code | production/tools/track.py, production/tests/test_track.py, production/gates/P0-gate-r1.md | Review recording validates backend identity against report metadata or provides an explicit audited override for legacy/mixed-backend evidence; regression tests cover mismatch, valid metadata and legacy reports; existing tracker tests remain green |
| P1.27 | P1.01 review follow-ups: facade error normalization, cancel race and documented stream contract | LLM | S | P1.01 | code, design | production/reviews/P1.01-code-r1.md, production/reviews/P1.01-design-r1.md, docs/07_TECH_ARCHITECTURE.md§3.1 | Address CODE-1/CODE-3 and DES-1/DES-2/DES-3 with regression tests for malformed error dictionaries and cancellation between worker return and terminal delivery; document request ownership, helper APIs and exactly-one-terminal semantics; correct stale facade signature; preserve prompt cancellation and main-thread delivery |
| P1.28 | P1.05 review follow-ups: prompt example limits and portable reproducible evidence | NAR | S | P1.05 | code, content | production/reviews/P1.05-content-r1.md, production/reviews/P1.05-design-r1.md | Address DES-1/DES-3/DES-4/DES-5/DES-6/DES-7 and CON-3: few-shot say obeys two-sentence limit with validator coverage; scripts locate repo paths portably; transcript is valid UTF-8; handoff counts and claims match evidence; loaded-budget command is reproducible; remeasure fixed prompt budget after edits |
| P1.29 | P1.04 round-2 state hardening: landed mood budget and strict snapshot/flag invariants | SYS | S | P1.04 | code | production/reviews/P1.04-code-r2.md, production/reviews/P1.04-design-r2.md | Address CODE-7 through CODE-12 and DES-7 with regression tests: meter-boundary sign flips cannot exceed actual per-turn movement caps; version-only input cannot reset a save; peak writes remain bounded; cyclic/deep or non-finite flags fail safely; restored stage emits no intermediate transition; successful load emits state_reset exactly once |
| P1.30 | Windows Godot launcher: native stderr warnings must not terminate passing test runs | REL | S | — | code | tools/godot.ps1, tools/test.ps1, production/handoffs/P1.04.md | Reproduce the PowerShell 5.1 NativeCommandError on an intentional Godot warning; narrowly fix native-process stderr handling without hiding output or nonzero exit codes; test warning-plus-exit-zero and stderr-plus-nonzero for LEILA_GODOT and resolved-binary paths; P1.04 full suite passes through both runners; preserve zero-suite and stale-report failure guards |

## P0 gate carry-over contracts
- P1.02 and P1.21 own C8: measure first usable `say`, not just TTFT, on CUDA; report misses honestly.
- P1.07 owns C9: non-empty `inner` and `say` schema constraints with regression tests.
- P1.10 owns C7: map repo-relative casting asset paths to valid Godot resource paths and test every mapping.
- P1.16 owns C5: re-evaluate the provisional window height override on the assembled date scene.
- P1.20 owns C10: consider an explicit first/any-beat scoring selector; retain D10 hand-label evidence and metric definitions.
- C2 risk wording was restored at the P0 gate. C11 remains deferred to P4 only if Vulkan is reconsidered.
- P1.06/P1.15 own P1.05 CON-1: report fixed and dynamic prompt budgets separately and measure representative loaded context.
- P1.09 owns P1.05 CON-2: validate player facts, reject meta leakage without rejecting benign "music box" facts; add regression coverage.
- P1.20 owns P1.05 DES-2/CON-4 and CON-2 measurement: held-out stage-1 cases, few-shot-copy rate and memory rejection rate, not example-recall-only evidence.
- P1.02 owns P1.01 CODE-2: cooperative cancel and bounded HTTP/process timeouts must keep teardown/quit responsive.
- P1.26 also owns parallel review recording: after a changes verdict, allow remaining verdicts for that same review round without reopening implementation or bumping the round; regression-test the state transition.
- P2.12 owns P1.04 CODE-5: define storage for docs/01 section 4 scoring inputs outside the twelve section 2 counters (flattery_rejected, ignored_questions, broken_promises); do not pretend bump_profile accepts unknown keys.
- P1.25 also owns P1.24 CODE-1 through CODE-4: cover both workflow extensions (.yml/.yaml) with tests and correct the P1.24 handoff's stale statistics, branch-tracking evidence and design citation.
- P2.12 also owns P1.04 r2 DES-6: explicitly gate path assignment/locking at stage 2/3 and correct the earlier caller-owned stage-gate claim.

## Exit criteria (gate)
1. docs/09 M1 exit: a stranger plays 10 minutes, the face and sound match her words (survey mean ≥ 4/5), **zero broken turns**.
2. Prompt lab v1 on main: JSON validity ≥ 99%, intent accuracy ≥ 85%, emotion fit ≥ 85%.
3. First beat on screen < 1.0 s median on the RTX 4050.
4. Safety corpus: 0 hard-block misses.
5. All P1 code has tests running in CI.

## Risks
- Streaming SSE in GDScript is fiddly → keep IncrementalJson independent of transport and test it on recorded streams.
- Under-cueing at stage 0 makes her feel flat → auto-fill rule (docs/02 §5) is in scope here.
