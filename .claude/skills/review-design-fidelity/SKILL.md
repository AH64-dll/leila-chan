---
name: review-design-fidelity
description: Design-fidelity review playbook for Leila-chan. Checks that a task's implementation matches the design bible (docs/01–10) and the five pillars, traces every requirement to its doc section, and judges any design change requests. Use when executing a review brief of kind "design".
---

# Review: design fidelity

You check that what was built is **what the design bible says**, and that any deviation is visible, justified and filed as a DCR.
You judge; you do not edit. Output: the report at the brief's path. Follow the work protocol §4–§5.

## Procedure
1. Read every ref in the brief **fully** (not just the cited section; neighbouring sections often constrain it).
2. Build a **trace table** in your report with one row per concrete requirement in those refs that falls in this task's scope:
   `| Req | Doc § | Implemented where (file:line / data key) | Matches? |`
3. Run the feature (the handoff's commands, a test scene, the prompt lab or transcripts) and compare observed behaviour with the doc.
4. Check the pillars (below). Check the handoff's "Deviations" and DCR section.
5. Findings `DES-n`. Verdict by the severity rules.

## Pillars (docs/01 §0). Every task is checked against them.
1. **She is not scripted.** No dialogue trees or canned lines where the model should improvise. Frames and fallbacks are fine.
2. **The game owns the truth, the model owns the voice.** State changes come from game rules. Model output is a clamped suggestion.
3. **Three engines of dread.** Slow burn always advances; paths come from player behaviour; triggers can spike.
4. **Her sickness is physical.** Later-stage weirdness comes from real steering dose, not only text effects.
5. **Fourth wall as a scalpel.** Rare, gated by stage, capped, offered (never free), always safe.

## What to look for
- Numbers that differ from the docs (thresholds, budgets, formulas, gates, timings) without a DCR → **S2**.
- Behaviour that contradicts a pillar → **S1** if it is player-visible, otherwise S2.
- Enums or names that don't exist in docs/02 §2, docs/03 §2 or `data/casting.json` → S2.
- Scope gaps: a requirement in the task's refs that is neither implemented nor deferred in the handoff → S2.
- Scope creep: features from later phases built now, risking rework → S3 (S2 if it adds safety surface).
- Data-driven expectation (docs/07 §2): content that a writer should tune is locked in code → S2.

## Judging DCRs
For each DCR in the handoff, write one of: **support** (good change; the producer should accept and update the doc), **reject**
(implement the doc as written), or **escalate** (touches pillars, safety rules, or docs/09 §4 decisions, so the user decides).
An unfiled deviation is always worse than a filed one. Note how the deviation was surfaced.

## Checklist
- [ ] Trace table covers every in-scope requirement of the refs
- [ ] Observed behaviour checked (not only code reading)
- [ ] All five pillars considered (one line each)
- [ ] Every deviation has a DCR verdict
- [ ] Later-phase dependencies noted (what this enables or blocks)
