# Phase-gate brief — P3 Paths & meta (gate round 1)

You are the **Phase-gate reviewer** for Leila-chan. Decide whether phase P3 has met its exit criteria and
whether the next phase may start. Also audit the reviewers, so that you are reviewing the reviews themselves.

## Read first

1. `AGENTS.md`
2. `.claude/skills/review-phase-gate/SKILL.md`: your gate playbook. Follow every step, including the review audit.
3. `production/phases/P3_paths_meta.md`, especially the **Exit criteria (gate)** section.
4. `production/STATUS.md` and `production/state.json` (read-only).

Work in the main tree at `/run/media/amrhares/New Volume/lila`, on the `main` branch, after all task branches are merged.

## Tasks in this phase

| Task | Status | Role | Agent | Review reports |
|---|---|---|---|---|
| P3.01 | done | STR | swe-2 | production/reviews/P3.01-code-r2.md, production/reviews/P3.01-design-r2.md |
| P3.02 | done | NAR | deepseek | production/reviews/P3.02-content-r2.md, production/reviews/P3.02-safety-r2.md |
| P3.03 | done | STR | swe2 | production/reviews/P3.03-code-r1.md, production/reviews/P3.03-design-r1.md |
| P3.04 | done | STR | swe2 | production/reviews/P3.04-code-r2.md, production/reviews/P3.04-design-r2.md |
| P3.05 | done | NAR | deepseek | production/reviews/P3.05-content-r3.md, production/reviews/P3.05-design-r3.md, production/reviews/P3.05-safety-r3.md |
| P3.06 | done | ART | deepseek | production/reviews/P3.06-code-r2.md, production/reviews/P3.06-design-r2.md |
| P3.07 | done | SYS | deepseek | production/reviews/P3.07-code-r3.md, production/reviews/P3.07-design-r3.md |
| P3.08 | done | META | deepseek | production/reviews/P3.08-code-r2.md, production/reviews/P3.08-design-r2.md, production/reviews/P3.08-safety-r2.md |
| P3.09 | done | META | swe2 | production/reviews/P3.09-code-r1.md, production/reviews/P3.09-design-r1.md, production/reviews/P3.09-safety-r1.md |
| P3.10 | done | META | swe2 | production/reviews/P3.10-code-r2.md, production/reviews/P3.10-design-r2.md, production/reviews/P3.10-safety-r2.md |
| P3.11 | done | META | swe2 | production/reviews/P3.11-code-r2.md, production/reviews/P3.11-design-r2.md, production/reviews/P3.11-safety-r2.md |
| P3.12 | done | SYS | swe-2 | production/reviews/P3.12-code-r2.md, production/reviews/P3.12-design-r2.md, production/reviews/P3.12-safety-r2.md |
| P3.13 | done | META | swe-2 | production/reviews/P3.13-code-r2.md, production/reviews/P3.13-design-r2.md, production/reviews/P3.13-safety-r2.md |
| P3.14 | done | META | deepseek | production/reviews/P3.14-code-r2.md, production/reviews/P3.14-design-r2.md, production/reviews/P3.14-safety-r1.md |
| P3.15 | done | NAR | deepseek | production/reviews/P3.15-content-r1.md, production/reviews/P3.15-design-r1.md, production/reviews/P3.15-code-r2.md |
| P3.16 | done | SYS | deepseek | production/reviews/P3.16-code-r1.md, production/reviews/P3.16-design-r1.md |
| P3.17 | done | NAR | deepseek | production/reviews/P3.17-content-r2.md, production/reviews/P3.17-design-r2.md, production/reviews/P3.17-safety-r2.md |
| P3.18 | done | SAFE | gemini-flash | production/reviews/P3.18-safety-r1.md |
| P3.19 | changes_requested | QA | swe2 | production/reviews/P3.19-code-r1.md, production/reviews/P3.19-design-r1.md |
| P3.20 | todo | QA | — | — |

## Output

Write `production/gates/P3-gate-r1.md` using `production/templates/gate_report.md`. The first line must be exactly
`GATE: PASS` or `GATE: FAIL`. Every exit criterion must have a status and evidence that you produced yourself, such as commands
run and their real output, metrics files, or playtest notes. Write down every review-audit finding, including the ones that show the
reviewers did their job.
