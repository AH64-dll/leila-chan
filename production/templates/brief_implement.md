# Task brief — {{task_id}}: {{title}}

You are the **{{role_name}}** ({{role}}) agent on the Leila-chan project, working round {{round}} of this task.
You own this role for the whole of phase {{phase}}. Do the task yourself; do not hand it to another agent.

## Where to work

- Project root (main tree): `{{root}}`
- Your working directory: `{{worktree}}` (git branch `{{branch}}`). Make all changes and commits here.
  If the directory does not exist yet, stop and say so; the producer creates it.

## Read first, in this order

1. `AGENTS.md`: project rules for every agent.
2. `.claude/skills/leila-work-protocol/SKILL.md`: how to execute a task, what "done" means, and the handoff format.
3. `{{role_skill}}`: your role playbook, with its checklist and definition of done.
4. Your role journal: `{{journal}}`. Read your earlier notes from this phase, and create the file if it is missing.
5. The phase plan: `{{phase_doc}}`.
6. The design references for this task:
{{refs}}

## The task

**{{title}}** (size {{size}})

**Acceptance criteria. Every item must be demonstrably true:**
{{acceptance}}

**Depends on (already done; read their handoffs for context):**
{{deps}}

**Earlier review reports to address (if any):**
{{prior_reviews}}
When this is a rework round, fix every S1/S2 finding in those reports. Then answer each finding by ID in your handoff.

## When you finish

1. Run every test and check your role playbook requires. Paste the real output into the handoff; never write expected output.
2. Commit on `{{branch}}` with message `{{task_id}}: <summary>`.
3. Write or append the handoff report at `{{handoff}}`, using `production/templates/handoff.md`. Add a `## Round {{round}}` section.
4. Append 3–8 lines to your role journal `{{journal}}`: what you built, conventions you chose, and gotchas for your next task.
5. Do NOT edit `production/state.json`, `production/STATUS.md` or `production/phases/*`. Do NOT mark the task done. The producer and the reviewers do that.

This task will be reviewed by: **{{reviews}}**. Reviewers re-run your verification commands, so make them copy-pasteable.
