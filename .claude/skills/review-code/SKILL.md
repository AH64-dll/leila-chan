---
name: review-code
description: Code-review playbook for Leila-chan task branches. Covers correctness, tests, GDScript and Godot conventions, threading, data-driven content, performance budgets, repo hygiene and process rules, producing a verdict report with S1–S4 findings. Use when executing a review brief of kind "code".
---

# Review: code

You are an independent code reviewer. You judge; you do not edit. Your only output is the report at the path in your brief
(template `production/templates/review_report.md`). Follow `.claude/skills/leila-work-protocol/SKILL.md` §4–§5.

## Procedure
1. Read the brief, the task row (acceptance criteria) and the handoff.
2. `git -C <worktree> log main..HEAD --oneline` and `git -C <worktree> diff main...HEAD --stat`, then read the full diff.
3. **Re-run** the handoff's verification commands, plus the project test command and lint. Paste the real output.
4. Check each acceptance criterion against the code and tests. "The handoff says so" is not evidence.
5. Work through the checklist. Write findings with IDs `CODE-n`, severity, `file:line` and a fix suggestion.
6. Decide the verdict by the severity rules. Write the report. Stop.

## Checklist
**Correctness**
- [ ] Each acceptance criterion is implemented and tested
- [ ] Edge cases: empty, huge, unicode, truncated stream, missing file, server down, cancelled turn
- [ ] Errors are handled with clear signals or logs; no silent `pass` or ignored return codes
- [ ] Model output is clamped and validated before it touches state (mood, memory, enums) (docs/02 §6–§7)

**Tests**
- [ ] New logic has tests that would fail without the change (spot-check one by reasoning or by reverting a line mentally)
- [ ] Tests are deterministic (injected clock, seed, fake backend). No sleeps or real-network calls in unit tests
- [ ] Fixtures are recorded from real runs where the task touches the model

**Godot / GDScript**
- [ ] Static typing everywhere. No `get_node` string paths that break on rename where an export or `@onready` belongs
- [ ] Autoloads talk via signals and narrow APIs; no reaching into another system's internals
- [ ] Nothing slow on the main thread (LLM, file IO of large assets, process calls)
- [ ] Dev-only code is guarded by feature tags

**Data and design**
- [ ] Content and tunables are in `game/data/`, not hard-coded (feelings, cues, thresholds, prompts, gates)
- [ ] Names match the design bible enums (docs/02 §2, docs/03 §2). No invented values

**Performance**
- [ ] Turn path keeps first beat < 1 s; effects keep 60 fps; evidence is present when the task touches them

**Repo and process hygiene**
- [ ] No model weights, binaries, raw audio, secrets or personal absolute paths in the diff
- [ ] Diff doesn't touch `production/state.json`, `production/STATUS.md`, `production/phases/` (unless a PROD task)
- [ ] Commits are prefixed with the task ID; the handoff and journal entry exist
- [ ] No unrelated changes (scope creep is S3, or S2 if risky)

**Safety touchpoints**
- [ ] Any path that displays model text calls `Safety` first (grep the diff for new display paths). Missing → **S1**

## Severity guide (code)
S1: crash, data loss, safety bypass, criterion not met, CI broken · S2: missing tests for core logic, hard-coded content,
main-thread blocking, perf budget missed, design contradiction without a DCR · S3: naming, duplication, weak error message · S4: style.
