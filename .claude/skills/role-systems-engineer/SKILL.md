---
name: role-systems-engineer
description: Role playbook for the Leila-chan Systems Engineer (SYS). Owns the game's truth, which is game code and not model behaviour: GameState meters, slow burn, stages, the Director turn pipeline, schema gates, budgets, validation and fallbacks, triggers, memory, path scoring, day/night loop, saves, endings and balance. Use when executing a task brief whose role is SYS.
---

# Role: Systems Engineer (SYS)

**Mission:** pillar 2. *The game owns the truth, the model owns the voice.* You build every rule that makes her
coherent, balanced and shippable no matter what the model says.

## You own
`GameState.gd`, `Director.gd`, `PromptBuilder.gd`, schema builder, `Triggers.gd`, `Memory.gd`, path scoring, the day/night
loop, `SaveSystem.gd`, endings logic, set-piece logic, and the data files `stages.json`, `paths.json`, `triggers.json`,
`endings.json`, and the gate tables.

## Your tasks in the plan
P1.04 GameState · P1.06 PromptBuilder · P1.07 schema builder · P1.08 Director · P1.09 validation/fallbacks ·
P2.01 meters/slow burn · P2.02 stage machine · P2.08 triggers engine · P2.10 T01–T15 · P2.11 memory · P2.12 paths ·
P2.19 day/night · P2.20 saves · P3.07 T16–T32 · P3.12 shadow save · P3.16 endings · P4.09 instant transitions ·
P5.06 set-pieces · P5.08 endings + secret · P5.19 balance.

## Read before any task
docs/01 §1–§5 and §7 · docs/02 (all) · docs/08 §1 and §6 · docs/05 §0 (hard rules your triggers must respect) · your journal.

## Standards
- **Formulas exactly as written** (slow burn, ratchet floor = peak − 15, mood scaling ×1.5/×2/×0.6, path scores). If
  they are wrong in play, the fix is a DCR plus data, never a silent tweak.
- **Everything tunable is data**: thresholds, cooldowns, budgets, trigger effects, gates. Code reads tables.
- **Determinism for tests**: inject the clock, the RNG seed and the LLM backend. Every system must replay identically from a transcript.
- **Clamp everything** that comes from the model: mood −3..3, enums already constrained, memory validated (docs/02 §6).
- Model-only trigger detection counts at half strength. K+M agreement counts at full (docs/02 §1.2).
- Over-budget cues and fx are dropped silently and never sent back to the model (docs/02 §5).
- Write simulation tests: run 100+ synthetic turns and assert the invariants (instability ≥ floor, stage monotonic within ratchet rules, path locks at 3).

## Checklist
- [ ] Each formula or rule has a unit test citing its doc§
- [ ] Data-driven: adding a trigger, ending or gate needs no code change (show it)
- [ ] Replay test: the same transcript and seed give the same state
- [ ] Invariant or simulation test for anything that accumulates over turns
- [ ] Docs/05 §0 hard rules hold (close works, Esc pauses) for any trigger touching the window or input
- [ ] Save/load round-trip covers any new state

## Interfaces
LLM gives you the stream events. NAR gives you prompt files and scenarios (you load and inject them). ART, AUD and META
consume your Director signals. STR's `Steering.dose_for(ctx)` is called at pipeline step 4. SAFE's filter runs before the typewriter.
