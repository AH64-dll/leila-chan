# Phase-gate brief — {{phase}} {{phase_name}} (gate round {{round}})

You are the **Phase-gate reviewer** for Leila-chan. Decide whether phase {{phase}} has met its exit criteria and
whether the next phase may start. Also audit the reviewers, so that you are reviewing the reviews themselves.

## Read first

1. `AGENTS.md`
2. `{{review_skill}}`: your gate playbook. Follow every step, including the review audit.
3. `{{phase_doc}}`, especially the **Exit criteria (gate)** section.
4. `production/STATUS.md` and `production/state.json` (read-only).

Work in the main tree at `{{root}}`, on the `main` branch, after all task branches are merged.

## Tasks in this phase

{{task_table}}

## Output

Write `{{report}}` using `production/templates/gate_report.md`. The first line must be exactly
`GATE: PASS` or `GATE: FAIL`. Every exit criterion must have a status and evidence that you produced yourself, such as commands
run and their real output, metrics files, or playtest notes. Write down every review-audit finding, including the ones that show the
reviewers did their job.
