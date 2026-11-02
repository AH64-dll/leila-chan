---
name: leila-work-protocol
description: The shared execution protocol for every Leila-chan agent, role or reviewer. Covers how to take a task brief from start to handoff, the definition of done, git and worktree rules, the severity scale and verdicts, design-change requests and escalation. Load it before executing or reviewing any task brief in production/briefs/.
---

# Leila-chan work protocol

Every agent on the project follows this protocol, whether it is SWE-2, DeepSeek, Claude or a human. Your role playbook
(`.claude/skills/role-*/SKILL.md`) or review playbook (`.claude/skills/review-*/SKILL.md`) adds the specifics.

## 1. The ground truth
- **Design bible:** `DESIGN.md` and `docs/01`–`docs/10`. It wins over your instincts. If it is wrong or silent, file a DCR (§6) and do not quietly invent behaviour.
- **Plan:** `production/phases/P*.md`. Your task row is the contract. Its acceptance criteria are the minimum, not a suggestion.
- **State:** `production/state.json` and `production/STATUS.md`. Only the producer writes them, through `production/tools/track.py`.
- **Pillars** (docs/01 §0). Check every decision against them. Pillar 2 matters most: *the game owns the truth, the model owns the voice.*
  Meters, stages, triggers, budgets and endings are game code. The model only suggests changes through the Turn JSON.

## 2. Executing a task (implementer)
1. Read your brief completely, then `AGENTS.md`, this file, your role playbook, your role journal and every ref in the brief.
2. Confirm you are in the working directory the brief names, on the right branch (`git branch --show-current`).
   If anything is missing (directory, dependency output, a local artifact), **stop** and report it in the handoff as BLOCKED. Do not improvise around it.
3. Plan in 3–10 bullets inside your head or scratch notes, then build in small commits (`<TASK_ID>: <what>`).
4. Content goes in data, not code. Feelings, cues, gates, triggers, scenarios and prompts live in `game/data/` (docs/07 §2).
5. Write tests alongside the code (gdUnit4/GUT for GDScript, pytest for Python, golden files for prompts/data).
6. Run the verification commands and capture the **real output**.
7. Write the handoff (`production/templates/handoff.md`) at `production/handoffs/<TASK_ID>.md`. Add a new `## Round N` section each round.
8. Append 3–8 lines to your role journal `production/journals/<PHASE>/<ROLE>.md`. The journal is how "you" persist through the phase across separate runs.
9. Stop. Do not mark anything done, merge, or touch `production/state.json`, `production/STATUS.md` or `production/phases/`.

### Definition of done (all must hold)
- Every acceptance criterion is met, with evidence (test name, file:line, metric, screenshot path).
- Tests pass locally; lint is clean; there are no new warnings in the Godot headless run.
- There are no secrets, absolute personal paths or model weights in the diff. Large binaries are only where the README says.
- Design deviations are listed (or "None"). Every rework finding is answered by ID.
- The handoff and the journal entry are written.

## 3. Git and worktrees
- Each task gets a worktree `D:/lila-wt/<TASK_ID>` on branch `task/<TASK_ID>`, created by the producer. Some tasks run in the main tree; the brief says when.
- Local-only artifacts live **only** in the main tree: `D:/lila/models/`, `D:/lila/tools/llama/`, `D:/lila/assets/audio/_raw/`. Refer to them by absolute path (or the `LEILA_MODEL` and `LEILA_LLAMA_DIR` env vars once P0.03 defines them). Never copy them into a worktree or into `game/`.
- Do not rebase or force-push. Do not touch other tasks' branches. The producer merges.

## 4. Reviewing a task (reviewer)
1. You judge; you do not fix. The only file you write is your review report.
2. Re-run the handoff's verification commands yourself. **A review with no evidence you produced is invalid.**
3. Check every acceptance criterion separately, then run your playbook's checklist.
4. Every finding gets an ID (`CODE-1`, `DES-2`, `CON-3`, `SAF-4`), a severity, a location and a suggested fix.
5. On a re-review, first verify every earlier S1/S2 is resolved, then review only what changed plus regressions.

## 5. Severity scale and verdicts
| Sev | Meaning | Examples |
|---|---|---|
| **S1 blocker** | Wrong, unsafe, or breaks the build or other systems | Safety-filter bypass; crash; acceptance criterion not met; data loss; meta event that can trap the player |
| **S2 major** | Must fix before merge | Design contradiction without a DCR; missing tests for core logic; hard-coded content that belongs in data; perf budget missed |
| **S3 minor** | Fix now or the producer tickets it | Naming, small duplication, unclear error message |
| **S4 nit** | Optional | Style preference |

- Any S1 or S2 → `VERDICT: CHANGES_REQUESTED`.
- Only S3/S4 → `VERDICT: APPROVED` (list them; the producer decides whether to carry them over).
- Cannot judge (missing branch, environment broken) → `VERDICT: BLOCKED` with the reason.

## 6. Design change requests (DCR)
If the design bible is wrong, impossible or silent:
- Implement the closest faithful version, or none if it would be harmful, and write a **DCR** in the handoff: which doc and section, the proposed text, why, and the impact.
- The producer accepts it (and schedules a doc update) or escalates it to the user. A DCR that touches the pillars, safety rules (docs/02 §8, docs/05 §0) or "decisions only you can make" (docs/09 §4) **always** goes to the user.

## 7. Escalation
Stop and report (BLOCKED, with the reason) when:
- a dependency's output is missing or wrong;
- the task needs a decision listed as OPEN in `production/DECISIONS.md`;
- you would have to weaken a safety rule, the content warning, or the "closing always works" rule;
- the task is bigger than its size (S ≈ 1–2 days, M ≈ a week, L ≈ several weeks of one developer). Propose a split instead.

## 8. Non-negotiables (all roles)
- Safety filter on every displayed model text, including leaked `inner` text, diary entries and letters (docs/02 §8).
- Meta events stay inside the game's window and `user://`. Closing always works on the second press, and Esc always pauses safely (docs/05 §0).
- No real mental disorder is ever named in game text (docs/01 §4 sensitivity rule).
- No Qwen/Alibaba logos or trademarks in art. The only allowed mention is the AWAKE factual line (docs/09 §3).
- Privacy: no telemetry by default, deleted drafts never leave memory, and the OS username is opt-in only.
