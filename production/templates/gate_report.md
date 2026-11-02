GATE: <PASS | FAIL>

# Phase gate — <PHASE> <name>, round <N>

- Date: <date> · Reviewer backend: <swe2 | deepseek | claude>
- Main branch commit: `<short sha>`

## 1. Task completion
<all tasks done with approved reviews for their final round? list any exception>

## 2. Exit criteria
| # | Criterion (from the phase doc) | Status | Evidence I produced |
|---|---|---|---|
| 1 | ... | pass / fail | command + output, metric file, playtest note |

## 3. Integration check on main
```
<build + test + prompt-lab commands run on main, with real output>
```

## 4. Review audit (reviewing the reviewers)
Sample: <which reviews, and why; at least 20% of approved reviews, at least 2, always including every safety review>
| Review report | Re-checked claim / criterion | Holds? | Missed defect (sev) | Reviewer quality |
|---|---|---|---|---|
| production/reviews/P1.03-code-r2.md | "IncrementalJson handles truncated stream" | yes | — | good |

Missed S1/S2 found → task re-opened: <list or "none">

## 5. Carry-overs
<S3/S4 findings, follow-up tasks proposed for the next phase (title, role, size)>

## 6. Risks and decisions
<new or changed risks for production/RISKS.md; decisions the user must make before the next phase>

## Verdict
<why PASS or FAIL. On FAIL, list exactly what must happen before re-gating.>
