---
name: leila-tracker
description: Track and report Leila-chan production progress. Covers the 0–100% formula, task statuses, the track.py commands, STATUS.md, decisions, risks, journals, review and gate records, and how to answer "where are we?". Use when the user asks for status, progress, percentage, what's blocked, who is doing what, velocity or ETA, or when any agent needs to record a state change.
---

# Leila-chan progress tracking

Everything is tracked in `production/`, and every number is computed. Nobody types a percentage.

## Where things live
| What | File | Who writes it |
|---|---|---|
| The plan (tasks, roles, sizes, deps, reviews, refs, acceptance) | `production/phases/P*.md` task tables | Producer only (append-only for new tasks) |
| Phase weights, roles, review kinds, dispatch commands | `production/config.json` | Producer, with user approval |
| Live state (status, round, agent, reviews, gates, history) | `production/state.json` | `track.py` only |
| Dashboard | `production/STATUS.md` | `track.py render` only |
| Decisions (open and closed) | `production/DECISIONS.md` | Producer; the user decides OPEN items |
| Risk register | `production/RISKS.md` | Producer, after each gate |
| Briefs sent to agents | `production/briefs/` | `track.py brief` / `gate-brief` |
| Handoffs | `production/handoffs/<ID>.md` | Implementer |
| Review reports | `production/reviews/<ID>-<kind>-r<N>.md` | Reviewer |
| Gate reports | `production/gates/<P>-gate-r<N>.md` | Gate reviewer |
| Role journals (agent memory through a phase) | `production/journals/<P>/<ROLE>.md` | Each role agent |
| Playtest material | `production/playtests/<P>/` | QA + the user |

## The 0–100% formula
- Task size points: **S = 1, M = 3, L = 8** (config `sizes`).
- **Phase %** = size points of `done` tasks ÷ all size points in the phase. A task counts only when it is `done`, which means
  every required review was approved for the final round and the branch was merged. Work in review is shown separately ("In review").
- **Project %** = Σ (phase weight × phase %). Weights: P0 4 · P1 18 · P2 16 · P3 18 · P4 12 · P5 20 · P6 7 · P7 5 = 100.
- A phase whose tasks are all done but whose gate has not passed shows 100% with status `active`. It is not `closed` until the gate passes.
- Adding tasks to a phase lowers its percentage. That is honest: the scope grew.

## Task statuses
```
todo → in_progress → in_review → done
            ↑            │
            └── changes_requested ←┘      (any → blocked → todo/in_progress, with a note)
done → in_progress   (reopen: gate audit found a missed defect, or tests broke after merge)
```
`track.py` enforces this. It also refuses to: start a task with unfinished deps; move to `in_review` without a handoff
file; mark `done` without approved reviews for the current round; accept a review from the implementer's own backend;
pass a gate with open tasks; or start a phase before the previous gate passed.

## Commands
```bash
python production/tools/track.py validate [--strict] [--verbose]   # plan sanity: ids, roles, deps, cycles, refs
python production/tools/track.py status [--phase P1]               # bars per phase + task list
python production/tools/track.py next [--phase P1]                 # ready tasks by role ([REWORK] = changes requested)
python production/tools/track.py start P1 [--note ...]             # activate a phase (previous gate must be closed)
python production/tools/track.py set P1.03 in_progress --agent swe2
python production/tools/track.py agent P1.03 deepseek              # fix backend after an automatic fallback
python production/tools/track.py set P1.03 in_review               # needs production/handoffs/P1.03.md
python production/tools/track.py review P1.03 code approved --report production/reviews/P1.03-code-r1.md --reviewer deepseek
python production/tools/track.py set P1.03 done
python production/tools/track.py set P1.07 blocked --note "needs decision D3"
python production/tools/track.py brief P1.03 [--kind code]         # writes the brief file, prints its path
python production/tools/track.py gate-brief P1                     # writes the gate brief
python production/tools/track.py gate P1 pass --report production/gates/P1-gate-r1.md
python production/tools/track.py render                            # regenerate STATUS.md
python production/tools/track.py report --days 7                   # done, rejected reviews, gates, velocity, ETA
```

## Answering "where are we?"
1. `track.py render`, then read `production/STATUS.md`.
2. Reply in at most 8 lines: overall %, the active phase with its % and task counts, what is in flight (task, role, agent),
   blockers with their reasons, OPEN decisions that need the user, and the next 1–3 dispatches.
3. Offer the full STATUS.md or the 7-day report if they want detail.

## Decisions and risks format
`production/DECISIONS.md` rows: `| D<n> | <question> | OPEN or DECIDED <date> | <answer> | <blocks tasks> |`.
STATUS.md counts rows that contain `OPEN`. When the user decides, change the row to `DECIDED <date>` and fill in the answer.
`production/RISKS.md` rows: `| R<n> | <risk> | L | I | <mitigation> | <owner role> | <status> |`.

## Journals
A role journal is the memory of the agent that "owns" a role through a phase. Every run of that role reads it first
and appends to it last: what was built, conventions chosen, gotchas, and things the next task in the role must know. The
producer reads all journals before the gate. The gate reviewer uses them to spot drift between roles.
