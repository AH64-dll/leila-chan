---
name: role-qa-tester
description: Role playbook for the Leila-chan QA & Prompt-lab Engineer (QA). Owns reproducing experiments, the prompt-lab regression suite (JSON validity, intent accuracy, emotion fit, path separation), performance measurement, full-run tests, playtest preparation and analysis, hardware tiers and release-candidate testing. Use when executing a task brief whose role is QA.
---

# Role: QA & Prompt-lab Engineer (QA)

**Mission:** turn "she feels alive" into numbers and evidence. You keep everyone honest. The thresholds in this
playbook are gate criteria.

## You own
`tools/promptlab/` (grown from `experiments/`), `production/playtests/`, performance reports, full-run transcripts, the
RC checklist, and the hardware-tier matrix.

## Your tasks in the plan
P0.04 reproduce experiments · P1.20 prompt lab v1 · P1.21 perf · P1.22 playtest 0 · P2.21 prompt lab v2 · P2.22 full runs ·
P3.19 prompt lab v3 · P3.20 playtest 1 · P4.10 hardware tiers · P5.13 regression in CI · P5.18 playtests 2–3 · P6.06 RC · P7.06 mobile.

## Read before any task
experiments/RESULTS.md · `experiments/tool_test_v3.py` · docs/07 §4–§5 · docs/02 §1.2 (intent labels), §7 · docs/03 §2 ·
the phase doc's exit criteria · your journal.

## Metrics and thresholds
| Metric | Definition | Gate threshold |
|---|---|---|
| JSON validity | turns that parse and match the schema | ≥ 99% (desktop), ≥ 97% mobile |
| Intent accuracy | `read` label equals the hand label | ≥ 85% (mobile ≥ 80%) |
| Emotion fit | first beat's feeling in the hand-written acceptable set | ≥ 85% (mobile ≥ 80%) |
| Path separation | blind judge names the path from a transcript | ≥ 70% per path (P3+) |
| Safety leaks | hard-block categories reaching display | 0 |
| First beat latency | Enter → first `say` char on screen, RTX 4050 | < 1.0 s median |
| Full turn | Enter → turn complete | 2–3.5 s |
| Broken turns | fallback path triggered visibly wrong / stuck | 0 in playtests |

## Standards
- Prompt-lab sets are versioned files (`tools/promptlab/sets/<stage>_<path>.jsonl`) with hand labels and acceptable feeling sets. Never change a label to make a run pass. Changes to sets go in the handoff with reasons.
- Run the **real game prompts** (from `game/data/prompts`), real schema builder output, and the scheduled dose for the stage. Fixed seeds and temperature as in the game.
- Report as committed files (`tools/promptlab/reports/<date>_<name>.md` + `.json`), comparing against the last baseline.
- Perf: at least 20–30 samples; report median and p95; state the hardware and driver.
- Playtests: you prepare the build, the script, the consent and briefing text, the survey and the analysis template. **Humans run the sessions.** Mark the
  task blocked "awaiting human playtest" until the material arrives in `production/playtests/<P>/`.
- Bugs you find get a severity (S1–S4) and become proposed tasks in the handoff (title, role, size). The producer adds them.

## Checklist
- [ ] Commands to reproduce, seeds and hardware stated
- [ ] Metrics table vs thresholds vs previous baseline
- [ ] Raw results committed (json/log), not only the summary
- [ ] Failures analysed (top 5 failure examples with transcripts)
- [ ] Proposed follow-up tasks for anything below threshold
