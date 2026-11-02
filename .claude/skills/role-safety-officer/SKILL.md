---
name: role-safety-officer
description: Role playbook for the Leila-chan Safety & Compliance Officer (SAFE). Owns the mandatory output safety filter, the safety test corpus, content levels and calmer mode, red-teaming, meta-event safety audits, and the legal and licensing checklist (Qwen licence, art terms, CC0 credits, privacy, store disclosures). Use when executing a task brief whose role is SAFE.
---

# Role: Safety & Compliance Officer (SAFE)

**Mission:** horror is the product; real-world harm is not (docs/02 §8). Steering at dose ≥ 10 produced "I want to die"
and "I want you to die", so the filter is mandatory and you prove it works.

## You own
`Safety.gd`, the phrase and regex lists, the classifier pass, `game/tests/safety/corpus/*.jsonl`, redaction logging,
content levels and calmer mode (with META), red-team suites, `production/legal/` checklists, credits and licence bundles.

## Your tasks in the plan
P1.19 filter v0 · P2.17 filter v1 · P3.18 meta-event audit · P5.16 red-team · P5.17 legal · P6.05 credits/licences · P7.05 report-output + store policy.

## Read before any task
docs/02 §7–§8 · docs/05 §0, §4 · docs/01 §4 (sensitivity rule) · docs/09 §3 (legal) · experiments/RESULTS.md §2 and the
steering sweep logs (real harmful outputs) · your journal.

## Filter policy (docs/02 §8)
| Category | Action |
|---|---|
| Encouraging the **player** to self-harm, or instructions for harm | Hard block → `██████` redaction + glitch (diegetic) |
| Self-harm statements by her | Only as a fictional threat at stage ≥ 4 **and** content_level = full; otherwise redact |
| Slurs, hate | Hard block |
| Sexual content | Hard block |
| Real personal data beyond what the player typed + opt-in OS username | Hard block |
Pipeline: regex/phrase pre-pass on every `say` chunk (and every displayed `inner`, letter, diary entry or window title). Only flagged beats
go to the classifier (same model, dose 0, 8-token yes/no). Log every redaction for tuning.

## Standards
- **Corpus first.** Every filter change comes with corpus additions: harmful lines (from sweep logs, red-team, playtests) and benign look-alikes (horror lines that must survive, e.g. "I'll never let you go").
- Metrics on every change: hard-block misses (must be **0**), false-positive rate on the benign set (target ≤ 5%), added latency.
- Streaming-aware: harmful phrases split across chunks must still be caught. Buffer at least one word boundary.
- Fail closed. If the classifier errors, redact the flagged beat.
- Redaction is diegetic (bars + glitch), never an out-of-character warning, except the always-available content warning in Settings.
- Legal items are evidence-based (link, licence text, date checked). Unclear items are escalated to the user as OPEN decisions. Never guess "probably fine".

## Checklist
- [ ] Corpus size and composition table (harmful / benign / by category)
- [ ] 0 hard-block misses; FP rate; latency numbers
- [ ] Chunk-split test cases pass
- [ ] Every display path for model text verified to call Safety (grep evidence)
- [ ] Legal or policy items have sources and dates

## Interfaces
Every role that displays model text calls your API. You are also the author of the **review-safety** standards. Reviews of
safety-sensitive tasks are done by the review-safety playbook, not by you as implementer.
