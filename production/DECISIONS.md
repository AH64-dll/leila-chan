# Decisions

The user decides OPEN items. The producer records answers here, and STATUS.md counts the OPEN rows.
Row format: `| D<n> | question | OPEN or DECIDED <date> | answer | blocks tasks |`

| ID | Question | Status | Answer | Blocks |
|---|---|---|---|---|
| D1 | Heroine name (docs/09 §4.1) | DECIDED 2026-11-01 | Leila-chan | — |
| D2 | Player identity (docs/09 §4.2) | DECIDED 2026-11-01 | Player types their name at New Game | — |
| D3 | Steering slider: ANCHOR-only reward (recommended) or post-game unlock for all paths? (docs/09 §4.3) | OPEN | | P3.10, P5.09 |
| D4 | Languages: English only at launch, or also Arabic (RTL UI + separate prompt tuning)? (docs/09 §4.4) | OPEN | | P5.15 |
| D5 | Content ceiling: stage-5 blood imagery (sprites 27, 30) on by default, or only behind the "full" content setting? (docs/09 §4.5) | OPEN | | P2.14, P5.11 |
| D6 | Project home: D:\lila is the repo root; Godot project lives in `game/` so root reference images are never imported | DECIDED 2026-11-02 | Proposed by the producer at planning time. The user can override before P0.05 | — |
| D7 | Agent backends: implementers via `~/.claude/bin/subagent` (SWE-2 → DeepSeek), reviewers on the other backend, Claude as producer | DECIDED 2026-11-02 | Matches the user's agent setup | — |
| D8 | Cloud saves on Steam: include or exclude the shadow save (`user://.leila/`)? | OPEN | | P6.01 |
| D9 | Legal read on the AWAKE line "I'm a Qwen model" and on the reference-render generator's commercial terms (docs/09 §3) | OPEN | | P5.17 |
| D10 | P0.04 metric DCR: "emotion fit ≥85%" gates on the published B4 any-beat "Fits" metric (met: 93.3%); the stricter first-beat promptlab gate (84.4% overall, 73.3% stage-4 — the Linux baseline itself scores 80.0%) is carried to P1.20 label-set quality review | DECIDED 2026-11-02 | Producer-accepted per P0.04 design-r2 review; do not relabel sets or re-run to chase 85% | — |
| D11 | P1.19 DCR-1: may explicit fictional threats directed at the player appear at late stages? | DECIDED 2026-11-03 | User approved gated fictional threats: only stage 4 or 5 AND explicitly selected full content. Missing settings must not imply full. Real-harm encouragement/instructions, sexual content, slurs and personal data remain hard-blocked in every context. This does not approve any other filter bypass or sensitivity exception. | — |
