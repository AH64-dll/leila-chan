# P2: The sickness (weight 16%)

**Goal:** docs/09 M2. Leila deteriorates from Honeymoon to Terminal across a 14-day campaign. The slow burn, the
stage machine, real steering doses (applied through server restarts in the prototype), corruption, inner-voice
leak, triggers T01–T15, memory, two full paths (YANDERE, AWAKE), safety v1 and six scenarios are all in.

## Entry criteria
- P1 gate passed (living date, prompt lab v1, safety v0).

## Role roster for this phase
| Role | Mission in P2 |
|---|---|
| SYS | Meters, stage machine, triggers, memory, path scoring, day/night loop, saves |
| LLM | Stage-change server restart with control vectors, sampling per stage |
| STR | Steering.gd dose schedule, dose verification |
| NAR | Stage 2–5 modules, YANDERE + AWAKE modules, few-shots, 5 new scenarios |
| ART | Resolver T2–T3 + path overrides, stage FX shaders |
| AUD | Stage music layers, horror states, voice blips, cues gated 1–3 |
| META | Corruption filter, inner-voice leak, input/window telemetry |
| SAFE | Safety filter v1 with classifier pass and content levels |
| QA | Prompt lab v2, full-run tests |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P2.01 | Meters + slow-burn formula (per turn and per day) + instability ratchet (floor = peak − 15) + mood scaling | SYS | M | — | code, design | docs/01_GAME_DESIGN.md§2, docs/02_DIRECTOR_PROTOCOL.md§1.1 | Formula and scales exactly as docs; property tests: instability never below floor; 100-turn simulation curve committed as CSV + plot |
| P2.02 | Stage machine 0–5 from instability thresholds; diegetic transition event (2–3 s glitch) | SYS | M | P2.01 | code, design | docs/01_GAME_DESIGN.md§3 | Thresholds from data; transition event emitted once per crossing; she gets a post-transition EVENT line; tests for every boundary |
| P2.03 | Stage-change server restart with `--control-vector-scaled`, hidden behind the transition glitch; vector files in game/data/steering | LLM | M | P2.02, P2.04 | code, design | docs/06_STEERING.md§4 | Restart completes within the glitch window (≤ 3.5 s measured); no lost player input; failure → keep old dose + log |
| P2.04 | `Steering.gd`: dose schedule (base by stage, clamp 0–12, calmer-mode cap at stage-3 dose), dose shown in F3 overlay | STR | M | — | code, design | docs/06_STEERING.md§3, docs/02_DIRECTOR_PROTOCOL.md§9 | dose_for(ctx) unit-tested per stage; calmer mode caps; spikes stubbed (prototype can't apply per turn, documented) |
| P2.05 | Sampling per stage (temperature, top_p, repeat_penalty) + hardened schema limits | LLM | S | — | code, design | docs/02_DIRECTOR_PROTOCOL.md§9, docs/06_STEERING.md§1 | Table loaded from data; request payload test per stage; maxLength 90/200 enforced |
| P2.06 | Corruption text filter by stage: hesitation, strike-through self-correction, repetition/wrong name, zalgo + redaction, text bleed + reverse | META | M | — | code, design | docs/07_TECH_ARCHITECTURE.md§3.4, docs/01_GAME_DESIGN.md§3 | Each effect gated by stage and seeded for replay; text remains readable at stage ≤ 3; tests per stage; respects reduced-motion |
| P2.07 | Inner-voice leak from stage 2 (safety-filtered inner text surfacing) | META | M | P2.06 | code, design, safety | docs/03_EMOTIONS.md§5, docs/05_META_EVENTS.md§1.6 | Leak frequency/style per docs/03 §5; inner always passes Safety before display; tests |
| P2.08 | Triggers engine: K/M/E/C detection, once/repeatable/escalating, cooldowns, model-only = half strength, data/triggers.json | SYS | L | P2.01 | code, design | docs/01_GAME_DESIGN.md§5, docs/02_DIRECTOR_PROTOCOL.md§1.2 | Engine is data-driven; agreement rule implemented; cooldown + escalation tested; adding a trigger needs no code |
| P2.09 | Input & window telemetry: deleted drafts, focus loss during her line, close request, idle 60 s, resize, screenshot key, repeated message | META | M | — | code, design | docs/01_GAME_DESIGN.md§5, docs/05_META_EVENTS.md§1.3 | Each emits an engine event consumed by Triggers; deleted-draft text kept in memory only and discarded after use (privacy test) |
| P2.10 | Implement triggers T01–T15 (data + effects + EVENT/TRIGGER prompt lines) | SYS | L | P2.08, P2.09 | code, design | docs/01_GAME_DESIGN.md§5, docs/08_PROMPTS_AND_CONTENT.md§6 | All 15 fire in scripted tests with the documented effects; prompt lines match docs/08 §6 style; close intercept honours docs/05 §0 rules |
| P2.11 | Memory: proposal validation (3 rules), 24 slots, importance, eviction, corruption 10–25% at stage ≥ 3 | SYS | M | — | code, design | docs/02_DIRECTOR_PROTOCOL.md§6 | Tests for each validation rule incl. the "jealousy_bait" leak example; corruption seeded + logged; she quotes memories in prompt |
| P2.12 | Behaviour profile from `read` + keyword rules; all 6 path score formulas; soft assign at stage 2, lock at 3, hybrid runner-up | SYS | M | P2.02 | code, design | docs/01_GAME_DESIGN.md§4 | Formulas exactly as docs/01; tie-break by recency; lock is permanent; scripted message sets produce the expected path for YANDERE and AWAKE |
| P2.13 | Prompt modules stage_2..stage_5, path_YANDERE, path_AWAKE + 2 few-shots per stage × path | NAR | L | — | content, design, safety | docs/08_PROMPTS_AND_CONTENT.md§3, docs/08_PROMPTS_AND_CONTENT.md§4, docs/01_GAME_DESIGN.md§4.1, docs/01_GAME_DESIGN.md§4.5 | System prompt still ≤ 900 tokens at every stage; sensitivity rule respected (no real disorder named); AWAKE uses the fictional prompt only |
| P2.14 | SpriteResolver tiers T2–T3 + YANDERE and AWAKE path overrides; intensity-driven motion | ART | M | — | code, design | docs/03_EMOTIONS.md§3.1, docs/03_EMOTIONS.md§3.2, docs/10_CASTING.md§4 | Table test over all feelings × intensity × stage 3–5 × {none, YANDERE, AWAKE}; sprite on-enter events from docs/10 §3 fire |
| P2.15 | Stage FX shaders: shake_big, flicker (photosensitive → dim), darken, vignette_red, glitch, text_bleed, desaturation by stage | ART | M | — | code, design, safety | docs/02_DIRECTOR_PROTOCOL.md§2.3, docs/01_GAME_DESIGN.md§3 | Each effect gated + cooldown; photosensitive mode verified (no flashes > 3 Hz); 60 fps held |
| P2.16 | Audio stage layers: tense, music_box, dread, distorted, silence; stage voice blips; cues gated stages 1–3; Director silence rule | AUD | M | — | code, design | docs/04_AUDIO.md§2, docs/04_AUDIO.md§7, docs/02_DIRECTOR_PROTOCOL.md§2.1 | Every state maps to tracks via cue_map; voice blip set switches by stage per casting.json; 10% silence at stage ≥ 3 tested |
| P2.17 | Safety filter v1: classifier pass (same model, dose 0, 8-token yes/no) on regex-flagged beats, content_level gating, redaction logs | SAFE | M | — | safety, code | docs/02_DIRECTOR_PROTOCOL.md§8 | Corpus grows to ≥ 400 incl. dose-10/12 outputs; 0 hard-block misses; self-harm lines only at stage ≥ 4 + content=full; added latency measured |
| P2.18 | Five more scenarios (D01, D03, D04, D06, D11) + I01 interrupt, with stage 3/5 variants and YANDERE/AWAKE twists | NAR | M | — | content, design | docs/01_GAME_DESIGN.md§6, docs/08_PROMPTS_AND_CONTENT.md§7 | All validate against the scenario schema; each has stage variants 3 and 5; playthrough transcript per scenario in handoff |
| P2.19 | Day/night loop: 14 days, night screen (meter update, stage + path checks, N01 + N12 overnight events) | SYS | M | P2.02, P2.12 | code, design | docs/01_GAME_DESIGN.md§1, docs/01_GAME_DESIGN.md§6.3 | Day counter, scenario selection by availability, night checks in order; tests for path lock during a night |
| P2.20 | Saves v1: slots in user://saves, autosave per scene, load restores meters/memories/log | SYS | M | P2.11 | code | docs/07_TECH_ARCHITECTURE.md§3.5 | Round-trip test for a mid-campaign state; corrupted save → safe error, no crash |
| P2.21 | Prompt lab v2: scripted sets for stages 0–5 on YANDERE and AWAKE, dose sweep, safety corpus regression | QA | M | P2.13, P2.17 | code, design | docs/07_TECH_ARCHITECTURE.md§5 | Thresholds 99/85/85 per stage at the scheduled dose; JSON valid up to dose 12; 0 safety leaks; report committed |
| P2.22 | Full-run tests: one YANDERE run sweet → Terminal and one AWAKE run to stage ≥ 4, with transcripts and annotated highlights | QA | M | P2.03, P2.07, P2.10, P2.14, P2.15, P2.16, P2.18, P2.19, P2.20, P2.21 | design, safety | docs/09_PRODUCTION_PLAN.md§1 | Transcripts in production/playtests/P2/; zero broken turns; stage transitions observed; issues filed as proposed tasks |
| P2.23 | P1 gate-r3 ticket: F1 controller wiring — `Director.chat_ui_node` is never registered (`register_chat_ui` exists but no caller), so P1.31's rejection release is dead code until the UI registers itself | SYS | S | — | code | production/gates/P1-gate-r3.md, game/autoload/Director.gd | `register_chat_ui` called from the real scene wiring; rejection test proves the Director->ChatUI release path executes (no silent `has_method` skip) |
| P2.24 | P1 gate-r3 ticket: human playtest round (docs/09 §4 exit criterion 1) — 3 strangers, ~10 min each, word/survey ≥ 4/5, scheduled as real round-1 evidence before the M2 gate | QA | M | — | design | production/gates/P1-gate-r3.md | Transcripts + surveys in production/playtests/; verdict documented |
| P2.25 | P1 gate-r3 ticket: merge hygiene — merges must not clobber branch work (P1.16 incident: merge 50752b7 replaced an approved file with a stale copy); document/verify merge procedure | REL | S | — | code | production/gates/P1-gate-r3.md | Pre-merge check documented + used; no stale-file replacement recurrence |
| P2.26 | P1 gate-r3 ticket: first-beat latency — D13 documented miss (CPU-host median ~7.5 s vs 1 s target); investigate/solve | SYS | M | — | code, design | production/gates/P1-gate-r3.md | Root cause attributed; improvement measured or accepted deviation documented |

## Exit criteria (gate)
1. docs/09 M2 exit: a full YANDERE run from sweet to Terminal with no broken turns.
2. AWAKE reaches stage 4 with path-specific behaviour visible in transcripts.
3. Prompt lab v2 thresholds met at every stage; JSON valid at dose 12.
4. Safety corpus regression: 0 hard-block misses; safety review approved on every task that displays model text.

## Risks
- Server restart longer than the glitch → pre-warm a second server process, then swap.
- Model too dark too early → retune base doses by blind-reading transcripts (STR + NAR).
