VERDICT: <APPROVED | CHANGES_REQUESTED | BLOCKED>

# <Review kind> review — <TASK_ID> round <N>

- Reviewer backend: <swe2 | deepseek | claude>
- Branch / commit reviewed: `task/<TASK_ID>` @ `<short sha>`
- Playbook: `.claude/skills/review-<kind>/SKILL.md`

## Acceptance criteria check
| # | Criterion | Verdict | How I checked |
|---|---|---|---|
| 1 | ... | met / not met / can't tell | command, file:line, or test |

## Verification I ran
```
<commands you ran yourself + their real output>
```

## Findings
| ID | Sev | Where (file:line) | Problem | Suggested fix |
|---|---|---|---|---|
| <KIND>-1 | S2 | `path:42` | ... | ... |

Severity: S1 blocker · S2 major (must fix) · S3 minor (fix or ticket) · S4 nit (optional).

## Earlier findings (re-review only)
| ID | Resolved? | Note |
|---|---|---|

## Checklist
<paste your playbook's checklist with [x] / [ ] / n/a per item>

## Summary
<2–4 sentences: the reason for the verdict.>
