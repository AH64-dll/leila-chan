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

A move does not exempt a file from that rule: keeping one parent's copy of a moved file is the same takeover,
whichever of the two names (old or new) holds the copy.

Two severities, deliberately asymmetric:

| Finding | Meaning | Blocks? |
|---|---|---|
| `STALE-COPY` | The merged file's blob id equals the **other parent's** blob, and this parent's delta lost lines. The P1.16 shape. Determined by blob ids, not judgement. | **yes** |
| `DELETED-BY-MERGE` | The merge dropped a file that a parent had changed (the modify/delete resolution that removed the four approved P1 handoffs, gate E34a). | **yes** |
| `DROPPED` | The resolution kept a merged blob but superseded individual added lines (two edits of the same line cannot both survive). Listed so the producer can see what changed hands. | no |
| `DELETE-VS-EDIT` (pre) | One side deleted a file the other side changed. The merge must pick one, so the report names the side that still holds the work and the copy to keep. | **yes** |
| `BOTH-DELETED` (pre) | Both sides deleted the same path since the merge-base. Git resolves delete/delete by deleting, and no line can be lost. Listed so the overlap count adds up. | no |
| `CONFLICT` (pre) | Both sides changed the same regions. The report names what each copy would lose if taken whole. | review |
| `RENAME/RENAME` (pre) | Both sides moved the same path — to two different new names, or to one name with different content. The report names every destination; identical copies move without a word. A move is not a deletion, so this is never `BOTH-DELETED`. | review |
| `RENAME/DELETE` (pre) | One side moved the file, the other side deleted it. The renamed copy is the only copy of the work, so the report says which path to keep. | **yes** |
| `RENAME/EDIT` (pre) | One side moved the file, the other edited it where it was. Git follows the move, so the verdict comes from the simulated result: a destination git cannot resolve is a `REVIEW`, and a merged copy that lost an added line fails. | review |

A rename is a deletion of the old path plus an addition of the new one, which is exactly why the listing disables
rename detection: a move must never hide the path the other side edited. The classification then looks the renames
up against the merge-base, so the four "gone from this path" shapes above can be told apart instead of all reading
as `BOTH-DELETED`.

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

Exit codes: **0** clean, **1** work is at risk, **2** the check could not run (bad ref, no merge in progress,
`--allow` in pre mode or an `--allow` that does not match a finding, a merge stopped while `--post HEAD` is asked
about the pre-merge commit, git missing from `PATH`, a git call that timed out).

`--post HEAD` audits the commit `HEAD` points at, so run it before another commit lands on top of the merge (the
journal/handoff commit included). After that, pass the merge commit id — `python tools/merge_check.py --post
3da2d24`. On a non-merge `HEAD` the tool answers `HEAD is not a merge commit (parents: 1)` with exit 2: that is
"the check could not run", not a pass. While a merge is stopped, `HEAD` is still the pre-merge commit, so
`--post HEAD` refuses with exit 2 and names `--staged` instead: auditing the old commit says nothing about the
merge in front of you.

A `--post` report prints `commit <40-hex>` under its header. That is the evidence line: any pasted report names the
exact tree it audited, so it cannot drift onto a later commit. `--json` carries the same id as `commit`.

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

Because it is a whitelist, three things are refused with exit 2 rather than accepted quietly:

- **anything that is not an exact repo-relative path** — a pattern (`production/*`), an absolute path or a `..`
  escape would acknowledge paths nobody read; `production/state.json` and `production/STATUS.md` cannot be
  acknowledged at all, since the audit already skips them;
- **a path that matched no finding** — a typo would otherwise read as "reviewed";
- **`STALE-COPY` and unresolved conflicts** — the P1.16 takeover is decided by blob id, not judgement, so it has to
  be undone rather than noted; an unresolved path has no resolution to acknowledge yet.

## Reading the report

Pre-merge on the real `task/P1.21` branch against the real `main` parent of the incident. The output is complete:
the `... N more` lines are the tool's own cap of eight examples per list, and the last line is its own summary of
the paths it did not report.

```console
$ python3 tools/merge_check.py --target feef716 7d7ae0b ; echo "pre exit=$?"
merge-check: pre-merge — target feef716 (feef716) ← source 7d7ae0b (7d7ae0b)
merge-base b90bb48
32 file(s) changed on both sides · 2 conflicted path(s)

  CONFLICT               game/tests/DateSceneTest.gd  target +16 / branch +45
      branch copy lacks 15 line(s) target added since the merge-base
      target copy lacks 38 line(s) the branch added since the merge-base
      taking the branch copy would delete:
      - # Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
      - for i: int in 25:
      - for i: int in 25:
      - func test_photosensitive_wiring() -> void:
      - _date.set_photosensitive(true)
      - assert_bool(_date.photosensitive).is_true()
      - assert_bool(_date.fx.photosensitive).is_true()
      - _date.play_fx(&"twitch")
      ... 7 more
      keeping the target copy would delete:
      - func test_vram_usage_budget_under_800mb() -> void:
      - # P1.21 Performance acceptance: Godot VRAM < 800 MB (Performance.RENDER_VIDEO_MEM_USED)
      - for i: int in 10:
      - var vram_bytes: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
      - var vram_mb: float = float(vram_bytes) / (1024.0 * 1024.0)
      - print(
      - "[P1.21] Godot VRAM used (Performance monitor): %d bytes (%.2f MB)" % [vram_bytes, vram_mb]
      - assert_int(vram_bytes).is_less(800 * 1024 * 1024)
      ... 30 more
  CONFLICT               production/journals/P1/ART.md  target +12 / branch +7
      branch copy lacks 5 line(s) target added since the merge-base
      taking the branch copy would delete:
      - ## P1.16 — Round 2 rework (2026-11-03)
      - - Addressed CON-1, DES-1 through DES-5, and CON-3.
      - - Gate C5 window sizing evaluated: set `window_width_override=384` and `window_height_override=688` in `project.godot`. …
      - - Wired `photosensitive` from `Settings` to `DateFX` (disables twitch flash) and forwarded scenario `ambience` to `Audio…
      - - Re-captured stills after 25 frames (>400 ms) so Character's 140 ms crossfade settles completely at 100% opacity.

  (30 other file(s) changed identically or auto-merge cleanly — no risk)

VERDICT: REVIEW — resolve the files above by hand and keep both sides.
  Then prove it: python3 tools/merge_check.py --post HEAD
pre exit=1
```

Post-merge on the incident commit, after the branch copy had been taken:

```console
$ python3 tools/merge_check.py --post 50752b7 ; echo "post exit=$?"
merge-check: post-merge audit — 50752b7^1 (feef716) vs 50752b7^2 (7d7ae0b)
commit 50752b7c2be16d571319438771d6a486440ff071
merge-base b90bb48

  STALE-COPY             game/tests/DateSceneTest.gd
      the merge result is the other parent's copy verbatim: 15 line(s) from its first parent (target) are gone
      - # Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
      - for i: int in 25:
      - for i: int in 25:
      - func test_photosensitive_wiring() -> void:
      - _date.set_photosensitive(true)
      - assert_bool(_date.photosensitive).is_true()
      - assert_bool(_date.fx.photosensitive).is_true()
      - _date.play_fx(&"twitch")
      ... 7 more
  DELETED-BY-MERGE       production/handoffs/P1.14.md
      the merge deleted this file, dropping 97 line(s) its second parent (branch) added:
      - # Handoff — P1.14: Boot → Title → NewGame (name entry 1–16 chars, safety check, empty → "Senpai") → Date scene flow
      - ## Round 1 (2026-11-03, agent: gemini-3.8-flash)
      - ### Summary
      - Implemented the full vertical slice scene flow: `Boot → Title → NewGame → Date`. Created `PlayerNameRules.gd` to enforce…
      - ### Acceptance criteria
      - | # | Criterion (copied from the plan) | Met? | Evidence (file:line, test name, metric) |
      - |---|---|---|---|
      - | 1 | Name rules of docs/08 §1.5 (basic set) tested | yes | `PlayerNameRules.gd`: 1–16 chars, allowed character set (`\p…
      ... 89 more

VERDICT: FAIL — the merge dropped work that a parent gained since the merge-base.
  Undo it (`git reset --hard ORIG_HEAD` before any further commits), redo the
  resolution keeping both sides, and re-run this check.
post exit=1
```

Delete-versus-edit names the copy that survives, in both directions, so the resolution cannot guess (scratch
repository, one file per direction):

```console
$ python3 tools/merge_check.py task/W          # the branch deleted it, the target still edits it
  DELETE-VS-EDIT         note.md
      the branch deleted this file; the target side changed it — keep the target copy
$ python3 tools/merge_check.py task/Z          # the target deleted it, the branch still edits it
  DELETE-VS-EDIT         note.md
      the target deleted this file; the branch side changed it — keep the branch copy
```

A move is classified as a move, never as a delete/delete (scratch repositories, each side moving `note.md`):

```console
$ python3 tools/merge_check.py task/R2         # both sides moved it, to two different names
merge-check: pre-merge — target HEAD (8107d4f) ← source task/R2 (a66865b)
merge-base 5fab00d
1 file(s) changed on both sides · 3 conflicted path(s)

  RENAME/RENAME          note.md
      the target renamed this path to main-side.md; the branch renamed it to branch-side.md
      both renamed copies hold work — keep both files

VERDICT: REVIEW — resolve the files above by hand and keep both sides.
  Then prove it: python3 tools/merge_check.py --post HEAD
exit=1
$ python3 tools/merge_check.py task/R          # the branch moved it, the target deleted it
merge-check: pre-merge — target HEAD (9b54c2a) ← source task/R (9c718bc)
merge-base 5fab00d
1 file(s) changed on both sides · 1 conflicted path(s)

  RENAME/DELETE          note.md
      the branch renamed this file to renamed.md; the target deleted it — keep renamed.md

VERDICT: FAIL — this merge cannot preserve both sides as-is; inspect the files above.
  Then prove it: python3 tools/merge_check.py --post HEAD
exit=1
```

The same audit passes on every P2 merge made before this ticket (`10e913c`, `c2e2873`, `0ac6c10`, `53b965d`,
`a58261e`, `bbe44f5`, `6d565e6`, `e62f484`) and on this branch's own `main` merge (`--post 3da2d24`), so it is not
a blanket red gate on healthy merges.

## How the check works

- `pre`: computes `git merge-base <target> <source>`, lists the paths changed on each side since that base
  (`--no-renames`, so a rename cannot hide the path the target edited), intersects them, and for every file in the
  intersection diffs **each side against the merge-base**. A path gone from a side is then looked up in that side's
  renames against the base (`--find-renames`), so delete/delete, rename/rename, rename/delete and rename/edit are
  told apart instead of all reading as deletions. It also simulates the merge with `git merge-tree --write-tree`
  (no worktree touched) to name the conflicted paths and to catch a clean merge that would still drop an added line;
  a conflicted path always means REVIEW at least, so no such shape can read as a pass. A plain delete/delete stays
  `BOTH-DELETED` and does not block: it has no line to lose, and failing it would contradict the post check that
  clears the same merge.
- `--post`: takes the merge commit's two parents and the same merge-base, then checks every line each parent
  added against the merge result. `STALE-COPY` when the result blob equals the other parent's blob. When the result
  no longer has a path, its renames against the merge-base are checked first, so a merge that followed a move is not
  called `DELETED-BY-MERGE` and dropping the moved copy still is. A moved path keeps the same blob comparison: the
  result is compared with the other parent's copy under the path, the destination and this side's rename origin,
  so taking one parent's copy wholesale under a move is `STALE-COPY` too.
- `--staged`: the same, with the index as the result and `MERGE_HEAD` as the second parent (renames come from
  `git diff --cached`). Unresolved paths fail.
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
*not* fail, delete-vs-edit in both directions (including the wording that names the copy to keep), both-sides
deletion, the three rename shapes — rename/rename to two names and to one, rename/delete, and the rename/edit that
git merges cleanly, followed through to the post check — the lossy resolution of a moved file in both directions
(keeping one parent's copy under a new name is `STALE-COPY`, not a warning), `--allow` on `--post`, its rejection in
pre mode, and the seven acknowledgments it refuses (a pattern, an absolute path, a `..` escape, a generated file, a
path that matched nothing, a stale copy, an unresolved conflict), whole-file deletion, the `track.py`-generated
exclusions, unresolved staged paths, the already-merged case, the `commit` evidence line, `--post HEAD` refusing
while a merge is stopped, and the exit-2 contract when git is missing from `PATH` or a git call times out. 34 cases,
no network and no project history: CI can run it on a shallow checkout.
