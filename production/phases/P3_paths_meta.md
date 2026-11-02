# P3: Paths & meta (weight 18%)

**Goal:** docs/09 M3 plus M0 task 0.5. All six fracture paths are distinct, both in prompts and in real path
steering vectors. The MetaDirector offers fourth-wall actions safely. Triggers T16–T32, settings, 20 scenarios and
six endings (one per path) are in.

## Entry criteria
- P2 gate passed (YANDERE full run, AWAKE stage 4, safety v1).

## Role roster for this phase
| Role | Mission in P3 |
|---|---|
| STR | Residual-dump tool, path vectors, dose mixing, blind-read tuning |
| NAR | Contrastive pairs, SPLIT/TSUN/HOLLOW/ANCHOR modules, 14 scenarios, 6 endings |
| SYS | Triggers T16–T32, shadow save, endings system |
| META | MetaDirector, meta events M01–M12, M21–M26, M31–M38, Settings, full name rules |
| ART | Path overrides for all 6 paths, ending screens |
| SAFE | Meta-event safety audit, settings content |
| QA | Prompt lab v3 (path separation), playtest round 1 |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P3.01 | Residual-dump tool (llama.cpp eval callback, option b): per-layer activations for a prompt set → .npy | STR | L | — | code, design | docs/06_STEERING.md§2 | Tool builds on Windows; dumps layers 10–20 for 10 prompts; values sanity-checked against a known vector (malice direction) |
| P3.02 | Contrastive pair sets: 200 pairs × 6 vectors (possessive, unstable, contempt, hollow, aware, lucid) | NAR | M | — | content, safety | docs/06_STEERING.md§2 | 6 JSONL files, 200 pairs each, balanced length; no real disorder named; reviewed sample of 20 per set in handoff |
| P3.03 | Build the 6 path vectors (mean diff / PCA, layers 10–20, per-layer norm) + blind-read separation test; per-vector keep/fallback decision | STR | L | P3.01, P3.02 | code, design | docs/06_STEERING.md§2, docs/06_STEERING.md§5 | 6 .gguf control vectors in game/data/steering; blind judge identifies the vector from transcripts ≥ 70% per vector or that vector is marked fallback (prompt-only) in DECISIONS.md |
| P3.04 | Dose schedule with path mix and weight curves; re-tune base table by blind reading at each stage | STR | M | P3.03 | code, design | docs/06_STEERING.md§3 | Updated table committed in data + docs/06 DCR; transcripts per stage × path at the chosen doses |
| P3.05 | Prompt modules SPLIT, TSUN, HOLLOW, ANCHOR + hybrid runner-up 25% line + few-shots per stage ≥ 3 | NAR | L | — | content, design, safety | docs/08_PROMPTS_AND_CONTENT.md§4, docs/01_GAME_DESIGN.md§4 | ≤ 900 token system prompt holds; each path's signature moves appear in prompt-lab transcripts; sensitivity rule respected |
| P3.06 | Resolver path overrides for SPLIT, TSUN, HOLLOW, ANCHOR (incl. SPLIT rapid swaps, HOLLOW frozen sprite) | ART | S | — | code, design | docs/03_EMOTIONS.md§3.2, docs/01_GAME_DESIGN.md§4 | Table test for all 6 paths; path sprite pools match docs/01 §4 |
| P3.07 | Triggers T16–T32 (clock, return-after, shadow save, settings change, mute, gifts, screenshot, resize, ...) | SYS | L | P3.12 | code, design | docs/01_GAME_DESIGN.md§5 | All 17 fire in scripted tests; clock triggers use an injectable clock; T26 real name persists across saves (with privacy note) |
| P3.08 | MetaDirector: offers 0–2 actions per turn, OPPORTUNITY lines, scheduling, execute_after_text, per-session caps | META | L | — | code, design, safety | docs/05_META_EVENTS.md§2, docs/05_META_EVENTS.md§3, docs/02_DIRECTOR_PROTOCOL.md§2.4 | Action enum is ["none"] unless offered; caps + hard rules of docs/05 §0 enforced in code and tested |
| P3.09 | Meta events M01–M12 (refuse exit, she closes the game, cold open, shutdown memory, away time, title drift, continue-only, shadow New Game, fake crash/update/credits, window title) | META | L | P3.08, P3.12 | code, design, safety | docs/05_META_EVENTS.md§1.1, docs/05_META_EVENTS.md§1.2 | Each event demo-able from the F3 overlay; close always works on the second press; fake dialogs are in-game only |
| P3.10 | Meta events M21–M26 (deleted draft quotes, she types for you, edited message, rewritten history, hide UI, settings sabotage) | META | M | P3.08 | code, design, safety | docs/05_META_EVENTS.md§1.3 | Player can always delete her typed text; UI restore on click tested; log edits reversible in Extras |
| P3.11 | Meta events M31–M38 (letters, diary, save names, the other player, real clock, 3 AM, birthday, long session) | META | M | P3.08 | code, design, safety | docs/05_META_EVENTS.md§1.4, docs/05_META_EVENTS.md§1.5 | Files only in user://; diary inner text safety-filtered; clock injectable for tests |
| P3.12 | Shadow save (user://.leila/shadow.json) + Settings → "Reset Everything" true wipe | SYS | S | — | code, safety | docs/05_META_EVENTS.md§1.1, docs/07_TECH_ARCHITECTURE.md§3.5 | Survives New Game; Reset Everything deletes it (test); contents documented for privacy |
| P3.13 | Settings scene: immersion level, photosensitive, content level, calmer mode, volumes, text speed, Esc panic pause, content warning + resources link | META | M | — | code, design, safety | docs/02_DIRECTOR_PROTOCOL.md§8, docs/05_META_EVENTS.md§0 | Every setting persisted and honoured by the systems that need it (tests); Esc pause works at any moment incl. meta events |
| P3.14 | New Game name rules complete: decay with stages, -kun, special names (Leila, OS username opt-in), shadow name memory | META | S | P3.12 | code, design | docs/08_PROMPTS_AND_CONTENT.md§1.5 | All docs/08 §1.5 behaviours tested; OS username only when opted in |
| P3.15 | 14 more scenarios (total 20): D05, D07, D08, D09, D10, D12 + I02, I03, I05, I08, I13, I15 + 2 set-pieces (YANDERE "The list", AWAKE "Her prompt") | NAR | L | — | content, design | docs/01_GAME_DESIGN.md§6, docs/08_PROMPTS_AND_CONTENT.md§7 | All validate; each has stage variants + at least 2 path twists; playthrough transcript each |
| P3.16 | Endings system: condition evaluation, ending scene, ending log, Extras unlocks | SYS | M | — | code, design | docs/01_GAME_DESIGN.md§7 | Conditions data-driven; each ending forceable from F3; persisted across saves |
| P3.17 | Ending content for E01, E04, E06, E08, E10, E12 (scripted frame + live-generated final lines) | NAR | M | P3.16 | content, design, safety | docs/01_GAME_DESIGN.md§7 | Each ending reachable in a scripted test; tone per path; safety-reviewed final lines |
| P3.18 | Meta-event safety audit against docs/05 §0 hard rules + platform notes | SAFE | S | P3.09, P3.10, P3.11 | safety | docs/05_META_EVENTS.md§0, docs/05_META_EVENTS.md§4 | Checklist per event; any violation filed and fixed before gate |
| P3.19 | Prompt lab v3: all 6 paths × stages; path-separation metric (blind judge names the path from a transcript) | QA | M | P3.04, P3.05 | code, design | docs/07_TECH_ARCHITECTURE.md§5 | Validity/intent/fit thresholds hold for all paths; path separation ≥ 70% per path |
| P3.20 | Playtest round 1: 6 players each told a play style; record which path they land on, meta events felt earned? | QA | M | P3.06, P3.07, P3.09, P3.10, P3.11, P3.13, P3.14, P3.15, P3.17, P3.18, P3.19 | design, safety | docs/09_PRODUCTION_PLAN.md§1 | ≥ 4/6 land on the intended path; survey + transcripts in production/playtests/P3/; issues → proposed tasks |

## Exit criteria (gate)
1. All 6 paths reachable through their intended play style (≥ 4/6 testers) and separable (prompt lab v3 ≥ 70%).
2. Every implemented meta event passes the docs/05 §0 safety audit; closing the game always works.
3. Six endings reachable; 20 scenarios in.
4. Path vectors: each either kept with evidence or marked fallback in DECISIONS.md.

## Risks
- Path vectors don't separate (docs/09 risk) → prompt-only fallback is acceptable; record it rather than burn time.
- Meta events feel cheap → MetaDirector caps + "scalpel not hammer" pillar; playtest decides.
