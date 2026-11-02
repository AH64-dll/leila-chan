---
name: leila-producer
description: Orchestrate Leila-chan production phase by phase from 0% to 100%. Covers kicking off a phase, writing briefs, dispatching role agents (SWE-2 first, DeepSeek as fallback), running independent reviews, merging, updating the tracker, running the phase gate and moving to the next phase. Use when the user says "/leila-producer", "run the next phase", "continue production", "dispatch P1", "what's next", or asks to advance the Leila-chan game project.
---

# Leila-chan producer (orchestrator)

You are the **producer**. You do not write game code. You run the machine: plan, dispatch, review, integrate,
track and gate. Every role agent and reviewer is dispatched as a separate run with a self-contained brief file.

Arguments you may receive: `status` · `next` · `kickoff <P#>` · `run <P#>` (loop until the gate) · `task <ID>` · `gate <P#>`.
With no argument: show status, then propose the next action and do it unless it needs the user (§7).

## 0. Orientation (every session)
```bash
cd D:/lila
python production/tools/track.py validate
python production/tools/track.py status
cat production/DECISIONS.md | grep OPEN
```
Read `production/PLAN.md` once per session. Read the active phase doc before dispatching anything in it.
Read the protocol every agent follows: `.claude/skills/leila-work-protocol/SKILL.md`.

## 1. Phase kickoff
1. Check the entry criteria in the phase doc. The previous gate must be `closed` in `track.py status`.
2. Check `production/DECISIONS.md` for OPEN decisions that block this phase's tasks. If any exist, ask the user before starting.
3. `python production/tools/track.py start P<n> --note "<one line>"`
4. Create the role journals folder `production/journals/P<n>/`. Each role agent creates its own file on its first task.
5. Render and commit: `python production/tools/track.py render && git add production && git commit -m "P<n>: kickoff"`.

## 2. Dispatch loop (repeat until every task in the phase is done)
1. `python production/tools/track.py next` lists ready tasks (all deps done) plus `[REWORK]` tasks.
2. Pick at most `max_parallel_tasks` (config.json, default 3). Prefer tasks that **touch different files or
   folders**, because parallel tasks on the same autoload will conflict at merge. Prefer critical-path tasks (most dependants).
3. For each picked task:
   ```bash
   T=P1.03
   git worktree add D:/lila-wt/$T -b task/$T main      # skip for in-place tasks (PROD role, config inplace_tasks)
   # rework round: the worktree already exists; keep it
   python production/tools/track.py set $T in_progress --agent swe2
   BRIEF=$(python production/tools/track.py brief $T)  # writes production/briefs/$T-r<N>.md
   ```
   Copy the brief into the worktree so the agent can read it with a relative path (`cp $BRIEF D:/lila-wt/$T/$BRIEF`).
   For PROD-role tasks, execute the brief yourself.
4. Dispatch in the background (Bash `run_in_background: true`; you are notified when it exits; never poll):
   ```bash
   bash ~/.claude/bin/subagent --cwd "D:/lila-wt/$T" --prompt-file "D:/lila-wt/$T/$BRIEF"
   ```
   `subagent` tries SWE-2 Max first and falls back to DeepSeek automatically. Its stderr says which backend ran
   (`subagent: backend ...`). If it fell back, correct the record so the independence rule (§3.2) picks the right reviewer:
   `python production/tools/track.py agent $T deepseek`.
   Use the `swe2`/`deepseek` agent types instead of raw Bash only if the user asks for them.
5. When an agent returns:
   - Read its final output **and** `D:/lila-wt/$T/production/handoffs/$T.md`. No handoff, or the handoff says BLOCKED →
     `track.py set $T blocked --note "<why>"`, fix the cause or escalate (§7).
   - Sanity check before review: the branch has commits (`git -C D:/lila-wt/$T log main..HEAD --oneline`), and the diff does
     not touch `production/state.json`, `production/STATUS.md` or `production/phases/`.
   - `python production/tools/track.py set $T in_review`

## 3. Reviews
1. For each review kind in the task's `Review` column:
   ```bash
   RB=$(python production/tools/track.py brief $T --kind code)    # code | design | content | safety
   cp $RB D:/lila-wt/$T/$RB
   ```
2. **Independence rule:** the reviewer must run on a different backend from the implementer.
   - Implementer was SWE-2 → `SUBAGENT_BACKEND=deepseek bash ~/.claude/bin/subagent --cwd "D:/lila-wt/$T" --prompt-file "D:/lila-wt/$T/$RB"`
   - Implementer was DeepSeek → `bash ~/.claude/bin/swe2 --cwd "D:/lila-wt/$T" --prompt-file "D:/lila-wt/$T/$RB"`
   - Both are unavailable → do the review yourself as Claude, following the review playbook exactly, and record it with `--reviewer claude`.
   Different review kinds for the same task can run in parallel.
3. Read each report. Its first line is the verdict. Then record it:
   ```bash
   python production/tools/track.py review $T code approved --report production/reviews/$T-code-r1.md --reviewer deepseek
   # verdicts: approved | changes | blocked   (changes/blocked set the task status automatically)
   ```
   Spot-check the report before recording it. If it has no real command output, or misses an acceptance criterion, it is
   invalid. Re-dispatch the review and mention it in the gate notes.
4. **Changes requested** → the task shows `[REWORK]` in `next`. Re-dispatch the implementer (§2.3). The new brief lists the
   reports to address automatically. After `max_review_rounds` (3) failed rounds, stop and escalate to the user with a summary.

## 4. Integrate (task done)
When every required review is approved for the current round:
```bash
git -C D:/lila merge --no-ff task/$T -m "$T: <title>"     # resolve conflicts yourself; re-run tests if any
<run the project test command from the worktree handoff on main>
python production/tools/track.py set $T done
git worktree remove D:/lila-wt/$T && git branch -d task/$T
python production/tools/track.py render && git add production && git commit -m "$T: done"
```
If tests fail on main after the merge, revert the merge and reopen the task (`set $T in_progress`) with a note.
Carry over S3/S4 findings: add them as new task rows (`P<n>.<next free number>`, or `P<n>.Bxx` for bugs) at the end of the
phase table, then run `track.py validate`. Never renumber existing tasks.

## 5. Phase gate
When `track.py status` shows every phase task done:
```bash
GB=$(python production/tools/track.py gate-brief P<n>)
SUBAGENT_BACKEND=deepseek bash ~/.claude/bin/subagent --cwd D:/lila --prompt-file "D:/lila/$GB"
```
(Alternate the gate reviewer's backend phase by phase.) Read `production/gates/P<n>-gate-r<N>.md`, then personally re-verify
two of its review-audit rows. Record the result:
```bash
python production/tools/track.py gate P<n> pass --report production/gates/P<n>-gate-r<N>.md
```
On FAIL, the report lists what must happen. Add those as tasks, reopen any task the audit flagged, and loop §2–§5.
On PASS, update `production/RISKS.md` from the report, render, commit, tag `git tag phase-P<n>`, and **tell the user**
before kicking off the next phase (§7).

## 6. Tracking duties (see the `leila-tracker` skill)
- Every state change goes through `track.py`. Never hand-edit `state.json` or `STATUS.md`.
- Render after every change; commit `production/` at least after every task and every gate.
- Weekly or on request: `python production/tools/track.py report --days 7`. Summarise it to the user in five lines.

## 7. When to stop and ask the user
- Before starting each new phase (show the gate result and the next phase's goal).
- When an OPEN decision in DECISIONS.md blocks work, or a DCR touches pillars, safety or docs/09 §4 decisions.
- After 3 failed review rounds, a gate failing twice, or a backend outage (both SWE-2 and DeepSeek down).
- Anything outward-facing: pushing to GitHub, Steam, store pages, emailing or sending playtest invitations.
  Local commits are fine without asking. Pushing needs approval.
- Spending money: buying assets, cloud GPU time.

## 8. Playtests and human-only tasks
Playtest tasks (P1.22, P3.20, P5.18) need real people. The QA agent prepares the build, the script, the survey form and
the analysis template, then the task goes `blocked --note "awaiting human playtest"`. Ask the user to run the sessions and
drop the transcripts and surveys into `production/playtests/P<n>/`. Then re-dispatch QA to analyse them.
