# Phase-gate brief — P2 The sickness (gate round 1)

You are the **Phase-gate reviewer** for Leila-chan. Decide whether phase P2 has met its exit criteria and
whether the next phase may start. Also audit the reviewers, so that you are reviewing the reviews themselves.

## Read first

1. `AGENTS.md`
2. `.claude/skills/review-phase-gate/SKILL.md`: your gate playbook. Follow every step, including the review audit.
3. `production/phases/P2_sickness.md`, especially the **Exit criteria (gate)** section.
4. `production/STATUS.md` and `production/state.json` (read-only).

Work in the main tree at `/run/media/amrhares/New Volume/lila`, on the `main` branch, after all task branches are merged.

## Tasks in this phase

| Task | Status | Role | Agent | Review reports |
|---|---|---|---|---|
| P2.01 | done | SYS | commandcode | production/reviews/P2.01-code-r2.md, production/reviews/P2.01-design-r2.md |
| P2.02 | done | SYS | commandcode | production/reviews/P2.02-code-r1.md, production/reviews/P2.02-design-r1.md |
| P2.03 | todo | LLM | — | — |
| P2.04 | done | STR | commandcode | production/reviews/P2.04-code-r2.md, production/reviews/P2.04-design-r2.md |
| P2.05 | done | LLM | commandcode | production/reviews/P2.05-code-r2.md, production/reviews/P2.05-design-r2.md |
| P2.06 | done | META | commandcode | production/reviews/P2.06-design-r1.md, production/reviews/P2.06-code-r1.md |
| P2.07 | todo | META | — | — |
| P2.08 | todo | SYS | — | — |
| P2.09 | done | META | commandcode | production/reviews/P2.09-design-r2.md, production/reviews/P2.09-code-r2.md |
| P2.10 | todo | SYS | — | — |
| P2.11 | done | SYS | commandcode | production/reviews/P2.11-code-r2.md, production/reviews/P2.11-design-r2.md |
| P2.12 | todo | SYS | — | — |
| P2.13 | done | NAR | commandcode | production/reviews/P2.13-design-r1.md, production/reviews/P2.13-safety-r1.md, production/reviews/P2.13-content-r1.md |
| P2.14 | done | ART | commandcode | production/reviews/P2.14-code-r2.md, production/reviews/P2.14-design-r2.md |
| P2.15 | done | ART | commandcode | production/reviews/P2.15-code-r3.md, production/reviews/P2.15-safety-r3.md, production/reviews/P2.15-design-r3.md |
| P2.16 | done | AUD | commandcode | production/reviews/P2.16-code-r1.md, production/reviews/P2.16-design-r1.md |
| P2.17 | done | SAFE | commandcode | production/reviews/P2.17-safety-r5.md, production/reviews/P2.17-code-r5.md |
| P2.18 | todo | NAR | — | — |
| P2.19 | todo | SYS | — | — |
| P2.20 | todo | SYS | — | — |
| P2.21 | todo | QA | — | — |
| P2.22 | todo | QA | — | — |
| P2.23 | done | SYS | commandcode | production/reviews/P2.23-code-r1.md |
| P2.24 | todo | QA | — | — |
| P2.25 | done | REL | commandcode | production/reviews/P2.25-code-r4.md |
| P2.26 | done | SYS | commandcode | production/reviews/P2.26-code-r2.md, production/reviews/P2.26-design-r2.md |

## Output

Write `production/gates/P2-gate-r1.md` using `production/templates/gate_report.md`. The first line must be exactly
`GATE: PASS` or `GATE: FAIL`. Every exit criterion must have a status and evidence that you produced yourself, such as commands
run and their real output, metrics files, or playtest notes. Write down every review-audit finding, including the ones that show the
reviewers did their job.
