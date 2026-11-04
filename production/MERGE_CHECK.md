# Merge hygiene — the pre-merge check and the post-merge proof

**Applies to:** every merge into `main` (the producer's integrate step, `.claude/skills/leila-producer/SKILL.md` §4).
**Tool:** `tools/merge_check.py` (stdlib Python + git plumbing; tests in `tests/test_merge_check.py`).
**Ticket:** P2.25, from the P1 gate-r3 finding E22.

## Why this exists

P1's merge `50752b7` (`task/P1.21` into `main`) conflicted in `game/tests/DateSceneTest.gd`. The resolution kept
the branch's copy of the file. That copy had forked before P1.16 landed, so the merge commit silently deleted the
approved P1.16 work — `test_photosensitive_wiring`, `test_ambience_forwarding` and the 25-frame capture settles —
and the gate only found it a day later (P1.32 had to restore the file byte for byte). The merge summary showed
`DateSceneTest.gd | 68 ++++--`, which reads like normal work, not like a deletion.

Git cannot warn about this: the branch *did* legitimately change the file, so "both sides changed it" is the
normal case. The defect is in the **resolution**, and a resolution is a human act. That is what the check audits.

## The rule

> A merge must keep every line each parent added since the merge-base. A file that comes out of the merge as the
> other parent's copy, verbatim, is a stale-file replacement and fails.

Two severities, deliberately asymmetric:

| Finding | Meaning | Blocks? |
|---|---|---|
| `STALE-COPY` | The merged file's blob id equals the **other parent's** blob, and this parent's delta lost lines. The P1.16 shape. Determined by blob ids, not judgement. | **yes** |
| `DELETED-BY-MERGE` | The merge dropped a file that a parent had changed (the modify/delete resolution that removed the four approved P1 handoffs, gate E34a). | **yes** |
| `DROPPED` | The resolution kept a merged blob but superseded individual added lines (two edits of the same line cannot both survive). Listed so the producer can see what changed hands. | no |
| `DELETE-VS-EDIT` (pre) | One side deleted a file the other side changed. The merge must pick one; look before it does. | **yes** |
| `CONFLICT` (pre) | Both sides changed the same regions. The report names what each copy would lose if taken whole. | review |

`production/state.json` and `production/STATUS.md` are excluded on purpose: `track.py` regenerates them from
`state.json` immediately after the merge (`set <TASK> done`, `render`), so their merged bytes prove nothing about
branch work. Everything else is audited, including handoffs, briefs and journals.

## The habit: three commands around every merge

From the main tree, with `$T` the task id and `task/$T` the branch:

```bash
python tools/merge_check.py task/$T          # 1. pre-merge: what is at stake, per changed file
git merge --no-ff task/$T -m "$T: <title>"   # 2. merge; resolve conflicts by hand, keep both sides
python tools/merge_check.py --post HEAD      # 3. post-merge: prove nothing was replaced
```

`--staged` is the same audit one step earlier, while the merge is stopped and the resolution is only staged:

```bash
git merge --no-ff task/$T -m "$T: <title>"   # stops on conflicts
# ...resolve, git add...
python tools/merge_check.py --staged         # catches a bad resolution before the commit exists
git commit --no-edit
```

Exit codes: **0** clean, **1** work is at risk, **2** the check could not run (bad ref, no merge in progress).

If the post check fails:

```bash
git reset --hard ORIG_HEAD     # or `git merge --abort` before the commit exists
# redo the resolution keeping both sides, then re-run the check
```

Do **not** resolve a conflicted file with `git checkout --theirs -- <file>` / `--ours` unless the report has
already told you that copy loses nothing. That is exactly the P1.16 mistake.

`--allow PATH` (repeatable, `--post`/`--staged` only) acknowledges a reviewed finding, e.g. a deliberate file
deletion; it turns a blocking finding into a reported `(allowed)` one. Use it only after reading the dropped
lines, and say why in the merge commit message.

## Reading the report

Pre-merge on the real `task/P1.21` branch against the real `main` parent of the incident:

```console
$ python3 tools/merge_check.py --target feef716 7d7ae0b
merge-check: pre-merge — target feef716 (feef716) ← source 7d7ae0b (7d7ae0b)
merge-base b90bb48
32 file(s) changed on both sides · 2 conflicted path(s)

  CONFLICT               game/tests/DateSceneTest.gd  target +16 / branch +45
      branch copy lacks 15 line(s) target added since the merge-base
      target copy lacks 38 line(s) the branch added since the merge-base
      taking the branch copy would delete:
      - # Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
      - for i: int in 25:
      - func test_photosensitive_wiring() -> void:
      ...
      keeping the target copy would delete:
      - func test_vram_usage_budget_under_800mb() -> void:
      ...

VERDICT: REVIEW — resolve the files above by hand and keep both sides.
  Then prove it: python3 tools/merge_check.py --post HEAD
```

Post-merge on the incident commit, after the branch copy had been taken:

```console
$ python3 tools/merge_check.py --post 50752b7
merge-check: post-merge audit — 50752b7^1 (feef716) vs 50752b7^2 (7d7ae0b)
merge-base b90bb48

  STALE-COPY             game/tests/DateSceneTest.gd
      the merge result is the other parent's copy verbatim: 15 line(s) from its first parent (target) are gone
      - # Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
      - for i: int in 25:
      - func test_photosensitive_wiring() -> void:
      ...

VERDICT: FAIL — the merge dropped work that a parent gained since the merge-base.
```

The same audit passes on every P2 merge made before this ticket (`10e913c`, `c2e2873`, `0ac6c10`, `53b965d`,
`a58261e`, `bbe44f5`, `6d565e6`, `e62f484`), so it is not a blanket red gate on healthy merges.

## How the check works

- `pre`: computes `git merge-base <target> <source>`, lists the paths changed on each side since that base
  (`--no-renames`, so a rename cannot hide the path the target edited), intersects them, and for every file in the
  intersection diffs **each side against the merge-base**. It also simulates the merge with
  `git merge-tree --write-tree` (no worktree touched) to name the conflicted paths and to catch a clean merge that
  would still drop an added line.
- `--post`: takes the merge commit's two parents and the same merge-base, then checks every line each parent
  added against the merge result. `STALE-COPY` when the result blob equals the other parent's blob.
- `--staged`: the same, with the index as the result and `MERGE_HEAD` as the second parent. Unresolved paths fail.
- Blank lines are ignored (they carry no information); binary and non-blob paths are reported for manual review;
  `--json` prints the whole report for scripts.

## Limits

- Line-based: a semantic regression that keeps every line (e.g. a value changed back) is not detected. That is a
  review's job.
- Additions only: a merge that resurrects a line the other side deliberately deleted is not flagged.
- Needs the merge base and both parents — the history must be present. CI checkouts are shallow, so this is a
  local/producer check, not a CI job (the CI job is `tools/test.sh` + `pytest`).
- The post check runs *after* the commit. Use `--staged` if you want to stop before the commit exists.

## Verifying the tool

```bash
python3 -m pytest tests/test_merge_check.py -q
```

The suite builds a synthetic repository with the P1.16 shape (main gains two tests, the branch forks before that
and edits the same file, the merge is resolved with the branch copy) and asserts the pre-check names the lost
lines and the post-check fails. It also covers a correct two-sided resolution, a same-line supersede that must
*not* fail, delete-vs-edit, whole-file deletion, the `track.py`-generated exclusions, unresolved staged paths and
the already-merged case.
