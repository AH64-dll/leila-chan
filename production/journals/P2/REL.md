# REL journal — P2

## P2.25 — merge hygiene gate (round 1, 2026-11-04, agent: commandcode)

- Built `tools/merge_check.py`: `pre` (default) diffs every file changed on both sides against the merge-base and
  prints what each copy lacks; `--post COMMIT` proves a merge kept both parents' added lines; `--staged` does it
  against the index before the commit exists. Documented in `production/MERGE_CHECK.md`; wired into the producer
  integrate step and the work protocol §3. 14 pytest cases rebuild the P1.16 shape in a synthetic repo.
- Convention: exit 1 in `pre` means "read the report before you resolve" (REVIEW); exit 1 in `--post`/`--staged`
  means "you dropped a parent's work, redo it". Both are documented + in `--help`; `--allow PATH` is the reviewed
  escape hatch, not a habit.
- The hard failure is the **takeover** signature, not any lost line: a merge result blob equal to the *other*
  parent's blob for a file the first parent changed (`50752b7` → `STALE-COPY DateSceneTest.gd`, 15 lines). A
  hand-merged blob that supersedes a same-line edit is a warning on purpose — failing every same-line conflict
  would train everyone to ignore the gate.
- Gotcha: `git merge-tree --write-tree` exits **1 on conflicts but still writes the result tree**; conflicted paths
  come from the `mode oid <stage>\tpath` records, and `-z` NUL-separates them. Use those records, not the exit code.
- Gotcha: `production/state.json` and `production/STATUS.md` are `track.py`-owned and regenerated after a merge;
  auditing their merged bytes is pure noise, so they are excluded by name (everything else, handoffs included, is
  audited — the check independently finds the E34a handoff deletions in `50752b7` and `84fee93`).
- CI cannot run this: `actions/checkout` is shallow and both audits need the merge base plus both parents. It is a
  producer/local gate; if it ever becomes a CI gate, fetch both parents and use `--post`.
