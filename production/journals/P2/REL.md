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

## P2.25 — round 2 (2026-11-04, agent: commandcode)

- Fixed the five round-1 findings: both-sides deletion is now `BOTH-DELETED` (reported, never blocking), so the pre
  check and `--post` cannot disagree about a merge git resolves by itself; delete-vs-edit now says which copy
  survives; `--allow` and the git-missing/timeout → exit 2 contract are tested (20 cases, was 14).
- Convention worth keeping: a finding that only means "look at this" must not block, and anything that blocks must
  be reproducible by `--post` on the same merge — otherwise the gate teaches people to ignore it. That rule is why
  delete/delete passes and why `--allow` exists only after a resolution.
- All git execution goes through one `_run_git()` guard. Never call `subprocess.run(["git", …])` directly in a gate:
  a missing binary or a hang must land on the documented exit 2, not a traceback that reads like lost work.
- Gotcha: `--post HEAD` is only valid while `HEAD` *is* the merge, and the journal/handoff commit moves it. Cite the
  merge id (`--post 3da2d24`) in evidence, or the reviewer re-runs the command and gets "not a merge commit" (exit 2).

## P2.25 — round 3 (2026-11-04, agent: commandcode)

- A rename is a deletion of the old path plus an addition of the new one, so the changed-path listing (which disables
  rename detection on purpose) sees every move as a delete. Never classify from that listing alone: look the side's
  own renames up against the merge-base (`--find-renames`) and report `RENAME/RENAME`, `RENAME/DELETE`, `RENAME/EDIT`
  — only a true delete/delete is `BOTH-DELETED`.
- The simulated merge is the oracle for a pre verdict: `git merge-tree --write-tree` exiting 1 on a path means the
  verdict can be REVIEW at worst, and the real `git merge` must be probed for every new status before shipping it.
  That probe is what caught rename/edit being a **clean** merge — failing it would have been a false alarm.
- Rename detection needs content: a one-line `README.md` moved and extended drops under git's 50% similarity threshold
  and becomes delete+add. Move fixtures need a file with real lines (`docs/notes.md`, eight).
- The post/staged audit must follow renames too (base→result), or a merge git resolved correctly comes back
  `DELETED-BY-MERGE`; the same rename map keeps the dropped-line list to the moved delta instead of the whole file.
- `--allow` is a whitelist: exact repo-relative paths only (no pattern, absolute path, `..` or generated file), every
  entry must match a finding, and a stale-copy takeover or unresolved path can never be acknowledged. `--post` prints
  the full audited commit id and refuses `--post HEAD` while a merge is stopped — HEAD is the wrong tree then.

## P2.25 — round 4 (2026-11-04, agent: commandcode)

- CODE-7: following a rename made `_audit_parents()` take the `if moved_to:` branch and skip the blob comparison, so a
  moved file resolved from one parent's copy verbatim was a non-blocking `DROPPED`/exit 0. The takeover test is now
  unconditional and looks at the other parent's copy under the audited path, the destination and this side's origin;
  `--staged` and `--post` both fail all three lossy shapes, and `render()` names the destination.
- Convention: the takeover rule is about **the blob**, not the path. A move changes where the copy lives, never whether
  one parent's whole delta may be replaced — any new "result exists, so nothing is lost" shortcut must keep the blob
  comparison.
- Test gotcha: assert the lossy move at `--staged` before committing (afterwards `HEAD^1`/`HEAD^2` change and
  `--post` is the only mode), and keep the move fixture ≥8 lines or git reports delete+add instead of a rename.
- `main` moved to eb6ca7f; merged as 4b3cf6c and `--post 4b3cf6c` passes. Suite 34 cases, full pytest 362 passed.
