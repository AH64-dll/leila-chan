# Leila-chan — master production plan (0% → 100%)

This plan turns the design bible (`DESIGN.md`, `docs/01`–`10`) into a shipped game. At the start there are 0 lines of game code.
At 100% the game is on Steam and the mobile ports are live. It is run by a **producer** (Claude, in this repo) that dispatches
**role agents** (SWE-2 Max first, DeepSeek V4.1 Flash as fallback, through `~/.claude/bin/subagent`) and **review agents** on a
different backend. Everything is tracked with `production/tools/track.py`.

## 1. Phases
| Phase | Name | Weight | Goal (one line) | Gate in one line | Tasks | Size pts |
|---|---|---:|---|---|---:|---:|
| [P0](phases/P0_bootstrap.md) | Bootstrap & environment | 4% | Windows dev env, repo in D:\lila, Godot skeleton, CI, tracker | Experiments reproduce on Windows; Godot boots; CI green | 10 | 20 |
| [P1](phases/P1_vertical_slice.md) | Vertical slice | 18% | One café date at stages 0–1 that feels alive | Stranger plays 10 min, face/sound match words, 0 broken turns | 22 | 66 |
| [P2](phases/P2_sickness.md) | The sickness | 16% | Stages 0–5, steering doses, triggers T01–T15, memory, YANDERE + AWAKE | Full YANDERE run sweet → Terminal | 22 | 79 |
| [P3](phases/P3_paths_meta.md) | Paths & meta | 18% | All 6 paths + path vectors, MetaDirector, meta events, settings, 20 scenarios, 6 endings | ≥ 4/6 testers land the intended path; meta events pass safety audit | 20 | 87 |
| [P4](phases/P4_native_runtime.md) | Native runtime | 12% | In-process llama.cpp, per-turn dose, caching, 3-OS builds | Builds run without external process; parity with server backend | 10 | 34 |
| [P5](phases/P5_content_complete.md) | Content complete | 20% | 70 scenarios, 14 + 1 endings, 43 meta events, final art/audio, legal | Content coverage 100%; regression suite green; 0 S1/S2 bugs | 19 | 100 |
| [P6](phases/P6_steam_launch.md) | Steam launch | 7% | Store page, trailer, Steamworks, RC, release | Game live on Steam | 8 | 18 |
| [P7](phases/P7_mobile.md) | Mobile | 5% | Smaller model, Android/iOS, first-launch download, store review | Both stores accept the build | 6 | 23 |
| | | **100%** | | | **117** | **427** |

Phases run **in order**. A phase starts only when the previous gate has passed. Inside a phase, tasks run in parallel (up to 3 at a
time) whenever their dependencies are done. The milestones match docs/09 M0–M6. P0 adds the Windows bootstrap that docs/09 assumed
was done, and P3 absorbs M0 task 0.5 (path vectors).

## 2. How progress is measured
- Task points: S = 1, M = 3, L = 8. A task counts **only when done**, which means every required review was approved and the branch was merged.
- Phase % = done points ÷ phase points. Project % = Σ phase weight × phase %.
- `python production/tools/track.py status` or `render` shows it. Nobody types a percentage.

## 3. Roles: one owning agent per role, for the whole phase
Each role is an agent identity defined by a playbook in `.claude/skills/role-*/SKILL.md`. Each dispatch is a fresh run, so
continuity comes from the **role journal** (`production/journals/<P>/<ROLE>.md`). Every run reads it first and appends to it last,
which makes "the LLM engineer of P1" one consistent owner from the first task of the phase to the last.

| Code | Role | Playbook | Owns |
|---|---|---|---|
| PROD | Producer (orchestrator) | `leila-producer` | Dispatch, reviews, merges, tracker, gates, user escalations |
| ENG | Engine Architect | `role-engine-architect` | Godot project, autoload wiring, tests, F3 overlay |
| LLM | LLM Integration Engineer | `role-llm-engineer` | llama.cpp, LLM facade, streaming, IncrementalJson, GDExtension |
| SYS | Systems Engineer | `role-systems-engineer` | Director, meters, stages, triggers, memory, paths, saves, endings |
| NAR | Narrative & Prompt Writer | `role-narrative-writer` | Prompts, few-shots, scenarios, endings, contrastive pairs |
| STR | Steering & ML Engineer | `role-steering-engineer` | Vectors, dose schedule, blind-read tuning |
| ART | Art & Character Engineer | `role-art-engineer` | Resolver, character, shaders/FX, backgrounds, store art |
| AUD | Audio Engineer | `role-audio-engineer` | AudioDirector, music states, cues, mix, licences |
| META | Meta-events & UX Engineer | `role-meta-ux-engineer` | UI, corruption filter, MetaDirector, 43 meta events, settings |
| SAFE | Safety & Compliance Officer | `role-safety-officer` | Safety filter, corpus, red team, legal |
| QA | QA & Prompt-lab Engineer | `role-qa-tester` | Prompt lab metrics, perf, playtests, RC |
| REL | Build & Release Engineer | `role-build-release` | Local artifacts, CI, builds, Steam, mobile builds |

### Who works in which phase (task counts)
| Role | P0 | P1 | P2 | P3 | P4 | P5 | P6 | P7 | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| PROD | 2 | · | · | · | · | · | 1 | · | 3 |
| ENG | 2 | 1 | · | · | · | · | · | · | 3 |
| LLM | 2 | 4 | 2 | · | 5 | · | · | · | 13 |
| SYS | · | 5 | 8 | 3 | 1 | 3 | · | · | 20 |
| NAR | · | 2 | 2 | 4 | · | 6 | · | · | 14 |
| STR | · | · | 1 | 3 | 1 | · | · | 2 | 7 |
| ART | 1 | 3 | 2 | 1 | · | 1 | 2 | · | 10 |
| AUD | · | 1 | 1 | · | · | 1 | · | · | 3 |
| META | · | 2 | 3 | 6 | 1 | 4 | · | 1 | 17 |
| SAFE | · | 1 | 1 | 1 | · | 2 | 1 | 1 | 7 |
| QA | 1 | 3 | 2 | 2 | 1 | 2 | 1 | 1 | 13 |
| REL | 2 | · | · | · | 1 | · | 3 | 1 | 7 |

## 4. Reviews: every task is reviewed by an independent agent
| Kind | Playbook | Required on | Count |
|---|---|---|---:|
| code | `review-code` | anything with code | 83 tasks |
| design | `review-design-fidelity` | anything implementing a doc section | 95 tasks |
| content | `review-content` | prompts, scenarios, endings, art content | 16 tasks |
| safety | `review-safety` | anything that displays model text, meta events, settings, legal | 30 tasks |
| gate | `review-phase-gate` | every phase end, **including an audit of the reviewers** | 8 gates |

The independence rule is that the reviewer runs on the other backend from the implementer (SWE-2 ↔ DeepSeek, or Claude when both are down).
Verdicts use one severity scale (S1–S4, `leila-work-protocol` §5). Any S1/S2 means changes requested. After 3 rounds the producer escalates to the user.

**Reviewing the reviewers:** each phase gate re-checks at least 20% of approved reviews (minimum 2) and *every* safety review.
A demonstrated missed S1/S2 re-opens the task and fails the gate. Repeated weak reports from one review kind trigger a
playbook fix. The producer then re-verifies two of the gate reviewer's audit rows.

## 5. The lifecycle of one task
```
plan row (phases/P*.md)
  → track.py brief         → production/briefs/<ID>-r<N>.md
  → git worktree D:/lila-wt/<ID>  (branch task/<ID>)
  → subagent (SWE-2 → DeepSeek)  reads AGENTS.md, protocol, role playbook, journal, refs
  → commits + production/handoffs/<ID>.md + journal entry
  → track.py set in_review
  → review briefs per kind → reviewer on the other backend → production/reviews/<ID>-<kind>-r<N>.md
  → approved?  yes → merge to main, tests on main, track.py set done, render STATUS.md
               no  → [REWORK] round N+1 with the reports attached (max 3, then the user)
```
At phase end: gate brief → gate reviewer → `production/gates/<P>-gate-r<N>.md` → `track.py gate <P> pass|fail`.

## 6. The user's part
- Approve the start of each phase (the producer asks).
- Decide the OPEN items in `production/DECISIONS.md` (steering slider, languages, content ceiling and others found later).
- Run human playtests (P1.22, P3.20, P5.18) with the material QA prepares.
- Approve anything outward-facing: GitHub pushes, Steam, store pages.

## 7. Start
In Claude Code inside `D:\lila`, type `/leila-producer kickoff P0`. To see where things stand at any time: `/leila-tracker`, or ask "status".
