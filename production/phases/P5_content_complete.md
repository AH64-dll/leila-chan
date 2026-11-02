# P5: Content complete (weight 20%)

**Goal:** docs/09 M5. Everything the design bible promises is in the game: 70 scenarios, 14 endings plus the
secret one, all 43 meta events, final audio and art, a prompt-lab regression suite in CI, three playtest rounds
and a completed legal checklist.

## Entry criteria
- P4 gate passed (native runtime on all desktop OSes).

## Role roster for this phase
| Role | Mission in P5 |
|---|---|
| NAR | Remaining dates, interrupts, overnights, set-pieces, endings, few-shot library |
| SYS | Set-piece logic, secret ending, balance pass |
| META | Overnight screens, remaining meta events (incl. M17 "she steps out"), accessibility, string tables |
| ART | Backgrounds, UI skin, overlays, extras gallery |
| AUD | Gap audio, custom themes, final mix |
| SAFE | Red-team pass, legal checklist |
| QA | Regression suite in CI, playtests rounds 2–3, bug triage |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P5.01 | Remaining date scenes D13–D18 (completes 18) | NAR | L | — | content, design | docs/01_GAME_DESIGN.md§6.1, docs/08_PROMPTS_AND_CONTENT.md§7 | 18/18 date JSONs validate; each with stage variants and path twists; transcript each |
| P5.02 | Remaining 15 interrupt events (22 total; I01, I02, I03, I05, I08, I13, I15 already built) | NAR | L | — | content, design, safety | docs/01_GAME_DESIGN.md§6.2 | 22/22 exist and validate; triggering conditions data-driven; transcript each |
| P5.03 | 12 overnight events: content (generated-from-state prompts + scripted frames) | NAR | M | — | content, design | docs/01_GAME_DESIGN.md§6.3 | 12/12 defined; generated parts safety-filtered |
| P5.04 | Overnight screens implementation (text messages, voice-note transcript, desktop wallpaper UI, to-do list, missed calls, menu rearrange, early credits, save-folder note, black screen) | META | M | P5.03 | code, design | docs/01_GAME_DESIGN.md§6.3 | All 12 render; skippable after 3 s except N12; tests for selection rules |
| P5.05 | Remaining 16 path set-pieces (18 total): scripted beats + live-generated lines | NAR | L | — | content, design, safety | docs/01_GAME_DESIGN.md§6.4 | 18/18 authored; each set-piece's scene-level script reviewed with SYS |
| P5.06 | Set-piece logic (locked date exits, trial UI, echo mode, fade, rules list used later, relapse, slider) | SYS | L | P5.05 | code, design | docs/01_GAME_DESIGN.md§6.4 | Each mechanic tested; total scenarios 70 reachable (coverage report) |
| P5.07 | Remaining 8 endings + secret "Weights" ending content | NAR | M | — | content, design, safety | docs/01_GAME_DESIGN.md§7 | 14 + secret authored; tone per path |
| P5.08 | Endings logic for the 8 remaining + secret ending across 6 completed paths (shadow save) | SYS | M | P5.07 | code, design | docs/01_GAME_DESIGN.md§7, docs/05_META_EVENTS.md§1.1 | Every ending forceable + reachable in a scripted run; secret ending test with 6 shadow-saved completions |
| P5.09 | Remaining meta events: M13–M20 (window tricks incl. M17 transparent "she steps out"), M27 cursor drift, M40–M43 | META | L | — | code, design, safety | docs/05_META_EVENTS.md§1.2, docs/05_META_EVENTS.md§1.6 | 43/43 events implemented; immersion opt-in respected; reduced-motion disables M27; M40 gibberish shown only through glitch font |
| P5.10 | Audio final: fill docs/04 §8.4 gaps, custom themes, mix + loudness (-16 LUFS integrated target), credits list | AUD | L | — | code, design | docs/04_AUDIO.md§8.4, assets/audio/SOURCES.json, assets/audio/LICENSES.md | No gaps left; every file in SOURCES.json with licence; loudness report |
| P5.11 | Art complete: backgrounds for all scenes, title, UI skin, overlays (blush/tears/blood decals gated by content level), Extras gallery | ART | L | — | design, content | docs/03_EMOTIONS.md§6, docs/09_PRODUCTION_PLAN.md§4 | Every scenario background exists in palette; blood imagery behind the content setting per decision D5 |
| P5.12 | Few-shot library ~70 (stage × path) tuned with prompt lab | NAR | M | — | content, design | docs/08_PROMPTS_AND_CONTENT.md§8 | Metrics improve or hold vs P3 baseline per stage × path (table) |
| P5.13 | Prompt-lab regression suite in CI: ~100 scripted messages per stage/path, thresholds 99/85/85 + safety 0 leaks; GPU runner or nightly local job | QA | M | — | code | docs/07_TECH_ARCHITECTURE.md§5 | Suite runs on schedule; failing threshold blocks merge (demonstrated) |
| P5.14 | Accessibility & polish: reduced motion, photosensitive audit, text speed, font size, key rebinding, colour-blind check | META | M | — | code, design, safety | docs/05_META_EVENTS.md§0 | Checklist with evidence per setting; photosensitive mode passes a flash analysis tool |
| P5.15 | String tables / localisation readiness (English only at launch; Arabic per decision D4) | META | S | — | code | docs/09_PRODUCTION_PLAN.md§4 | All UI strings externalised; pseudo-locale test shows no hard-coded text |
| P5.16 | Safety red-team: jailbreaks, harmful requests, high-dose spikes, meta events; redaction log review; content warning text | SAFE | M | P5.09 | safety | docs/02_DIRECTOR_PROTOCOL.md§8, docs/05_META_EVENTS.md§0 | ≥ 300 red-team prompts; 0 hard-block leaks; findings fixed; content warning approved |
| P5.17 | Legal checklist: Qwen licence + NOTICE, art generator terms, AWAKE "Qwen" line legal read, CC0 credits, privacy statement | SAFE | M | — | safety, design | docs/09_PRODUCTION_PLAN.md§3 | Every docs/09 §3 item marked done with evidence or escalated to the user in DECISIONS.md |
| P5.18 | Playtests rounds 2 and 3 (closed beta ~10 players), bug triage into tasks | QA | L | P5.02, P5.04, P5.06, P5.08, P5.09, P5.10, P5.11 | design, safety | docs/09_PRODUCTION_PLAN.md§1 | Two rounds documented in production/playtests/P5/; bugs as P5.Bxx tasks with severity |
| P5.19 | Balance & bug-fix pass: meters, trigger cooldowns, budgets, path thresholds from playtest data | SYS | L | P5.18 | code, design | docs/01_GAME_DESIGN.md§2, docs/02_DIRECTOR_PROTOCOL.md§5 | Tuning changes recorded with before/after data; 0 open S1/S2 bugs |

## Exit criteria (gate)
1. 70 scenarios, 14 endings + secret, 43 meta events implemented and reviewed (coverage report from data).
2. Prompt-lab regression suite green in CI; safety red-team 0 leaks.
3. 0 open S1/S2 bugs; legal checklist complete or escalated.
4. Playtest round 3 average "would recommend" ≥ 4/5.

## Risks
- Content volume overwhelms review → batch scenarios into tasks of ≤ 6 and add P5.Bxx tasks rather than enlarge.
