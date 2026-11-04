#!/usr/bin/env python3
"""Merge-hygiene gate: a merge must never drop work that one side gained.

P2.25 exists because of P1.16. Merge `50752b7` (task/P1.21) hit a conflict in
`game/tests/DateSceneTest.gd` and was resolved by keeping the branch copy, which
silently deleted `test_photosensitive_wiring`, `test_ambience_forwarding` and the
25-frame capture settles that main had gained from P1.16. The clash looked like
an ordinary conflict; the loss was invisible in the merge summary.

Two questions, one tool:

  pre   (default) Before merging, which files changed on BOTH sides since the
        merge-base, and what would each copy lose? Per file, this diffs each
        side against the merge-base and reports the lines the other side never
        saw. It exits 1 when a conflict is at stake with lines either copy
        lacks (the P1.16 shape), or when a delete/edit race exists.

  --post COMMIT
        After merging, did the merge commit keep every line each parent gained
        since the merge-base? This is the hard control: a file that comes out as
        the other parent's copy verbatim is a stale-copy replacement and fails.
        Individual added lines superseded by a two-sided resolution are listed
        but do not fail (two edits of one line cannot both survive).

  --staged
        The same audit one step earlier, against the index while a merge is in
        progress and before the merge commit exists (HEAD vs MERGE_HEAD).
        Unresolved paths fail.

Usage:
    python3 tools/merge_check.py task/P1.21          # target defaults to HEAD
    python3 tools/merge_check.py --target main task/P1.21
    python3 tools/merge_check.py --post HEAD
    python3 tools/merge_check.py --staged
    python3 tools/merge_check.py --post HEAD --allow production/handoffs/P1.14.md
    python3 tools/merge_check.py --json task/P1.21

Exit codes: 0 clean, 1 work is at risk, 2 the check could not run.

Design notes:
- "Work" is measured as lines added relative to the merge-base, not as commits or
  mtimes: a file that main edited and the branch never touched cannot be lost by
  the merge, and a line that already existed on both sides proves nothing.
- Blank lines are ignored (they carry no information and would drown the report).
- Non-blob paths (submodule gitlinks) and binary files are reported as
  manual-review items instead of being line-compared.
- Renames are disabled while listing changes so a branch rename shows up as a
  delete (of the path main may have edited) plus an add, never as a silent move.
  The side's own renames are then looked up against the merge-base: a move is
  not a loss by itself, so RENAME/RENAME, RENAME/DELETE and RENAME/EDIT are
  reported by name instead of being folded into BOTH-DELETED (P2.25 CODE-1).
- A path the simulated merge still conflicts on can never read as a pass: the
  report says REVIEW at least, whatever the per-path status says (CODE-6).
- `--allow` is a whitelist, so it takes exact repo-relative paths only — no
  pattern, no absolute path, no `..`, no generated file — and every entry must
  match a finding the audit may acknowledge. A stale-copy takeover is never
  allow-able: it is the P1.16 defect itself (CODE-2).
- The post/staged report names the commit id it audited (`commit <sha>`) so a
  pasted report is tied to the tree it describes, and `--post HEAD` refuses
  while a merge is stopped, when HEAD is still the pre-merge commit (CODE-3).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Callable

EXIT_OK = 0
EXIT_ATTENTION = 1
EXIT_ERROR = 2

MAX_EXAMPLES = 8
MAX_EXAMPLE_CHARS = 120

# Files the producer regenerates from production/state.json with `track.py`
# right after a merge (`render`, `set <TASK> done`). Auditing their merged
# content would flag every concurrent producer edit as lost work while proving
# nothing about branch work: the next track.py run overwrites the merge copy.
# Everything else — including other producer-owned files — is audited.
GENERATED_PATHS = frozenset({"production/state.json", "production/STATUS.md"})

STAGE_LINE = re.compile(rb"^\d{6} [0-9a-f]+ [123]\t(.+)$", re.S)


class GitError(RuntimeError):
    """A git invocation the check needs failed; the check cannot answer."""


# --------------------------------------------------------------------------- git


def _run_git(args: tuple[str, ...], timeout: int) -> subprocess.CompletedProcess[bytes]:
    """Run git, turning "it did not run" into the documented exit 2.

    A missing binary or a hung git is not evidence about the merge: it must not
    read as exit 1 ("work is at risk") or as a traceback the producer has to
    interpret. Both callers below share this one guard.
    """
    try:
        return subprocess.run(
            ["git", "--literal-pathspecs", *args],
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise GitError("git is not installed") from exc
    except subprocess.TimeoutExpired as exc:
        raise GitError(f"git {' '.join(args)}: timed out after {timeout}s") from exc


def git(*args: str, timeout: int = 120) -> bytes:
    """Run git and return stdout; raise GitError with git's own words on failure."""
    proc = _run_git(args, timeout)
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace").strip() or f"exit {proc.returncode}"
        raise GitError(f"git {' '.join(args)}: {detail}")
    return proc.stdout


def git_soft(*args: str, timeout: int = 120) -> tuple[int, bytes]:
    """Run git and return (exit code, stdout) without raising; for expected misses."""
    proc = _run_git(args, timeout)
    return proc.returncode, proc.stdout


def commit_of(ref: str) -> str:
    """Resolve a ref to a commit id, or raise GitError with a readable reason."""
    code, out = git_soft("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if code != 0 or not out.strip():
        raise GitError(f"not a commit: {ref}")
    return out.decode().strip()


def merge_base(a: str, b: str) -> str:
    code, out = git_soft("merge-base", a, b)
    if code != 0 or not out.strip():
        raise GitError(f"no common ancestor between {a} and {b}")
    return out.decode().strip()


def changed_paths(base: str, tip: str) -> list[str]:
    """Paths whose content differs between base and tip (renames disabled)."""
    out = git("diff", "--name-only", "-z", "--no-renames", base, tip)
    return [os.fsdecode(p) for p in out.split(b"\0") if p]


def blob_of(rev: str, path: str) -> str | None:
    code, out = git_soft("rev-parse", "--verify", "--quiet", f"{rev}:{path}")
    if code != 0 or not out.strip():
        return None
    return out.decode().strip()


def object_type(rev: str, path: str) -> str | None:
    """blob, tree, commit (submodule gitlink) or None when the path is absent."""
    blob = blob_of(rev, path)
    if blob is None:
        return None
    code, out = git_soft("cat-file", "-t", blob)
    if code != 0:
        return None
    return out.decode().strip()


def content_of(rev: str, path: str) -> bytes | None:
    """Raw bytes at rev:path, or None when the path does not exist there."""
    code, out = git_soft("show", f"{rev}:{path}")
    if code != 0:
        return None
    return out


def is_binary(data: bytes) -> bool:
    return b"\0" in data[:8000]


def text_lines(data: bytes) -> list[str]:
    return data.decode("utf-8", "replace").splitlines()


def _added_lines_from(diff: bytes) -> list[str]:
    """The non-blank `+` lines of a -U0 diff, headers excluded."""
    lines: list[str] = []
    for raw in diff.decode("utf-8", "replace").splitlines():
        if raw.startswith("+++") or raw.startswith("---"):
            continue
        if raw.startswith("+") and raw[1:].strip():
            lines.append(raw[1:])
    return lines


def added_lines(base: str, tip: str, path: str) -> list[str]:
    """Non-blank lines the tip added to path relative to base.

    Line-based on purpose: it is the unit the producer can act on ("this test
    function is gone"), and it survives whitespace-only churn being ignored.
    """
    out = git("diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, tip, "--", path)
    return _added_lines_from(out)


def moved_added_lines(base: str, tip: str, old: str, new: str) -> list[str]:
    """Lines the tip added to a path it renamed old -> new.

    `added_lines()` disables rename detection, so on a moved file it would call
    every line of the new copy "added". Here both ends are in the pathspec, so
    git pairs them and only the real additions remain (P2.25 CODE-1).
    """
    out = git(
        "diff", "-U0", "--no-color", "--no-ext-diff", "--find-renames",
        base, tip, "--", old, new,
    )
    return _added_lines_from(out)


def _parse_renames(out: bytes) -> dict[str, str]:
    """Old path -> new path from `--name-status -z` output (R records only)."""
    fields = out.split(b"\0")
    mapping: dict[str, str] = {}
    index = 0
    while index < len(fields) and fields[index]:
        status = fields[index]
        if status.startswith(b"R") and index + 2 < len(fields):
            mapping[os.fsdecode(fields[index + 1])] = os.fsdecode(fields[index + 2])
        index += 3 if status.startswith((b"R", b"C")) else 2
    return mapping


def renames(base: str, tip: str) -> dict[str, str]:
    """Old path -> new path for every rename between two commits."""
    return _parse_renames(
        git("diff", "--name-status", "-z", "--find-renames", "--diff-filter=R", base, tip)
    )


def index_renames(base: str) -> dict[str, str]:
    """Old path -> new path for every rename between a commit and the index.

    The staged audit has no result commit to diff against, and a merge that
    follows a rename leaves the old path absent from the index too.
    """
    return _parse_renames(
        git(
            "diff", "--name-status", "-z", "--find-renames", "--diff-filter=R",
            "--cached", base,
        )
    )


def merge_tree(target: str, source: str) -> tuple[str | None, set[str]]:
    """Simulate the merge without touching the worktree.

    Returns (result tree id, conflicted paths). git merge-tree writes the would-be
    tree into the object database (dangling unless referenced) and exits 1 when
    any path conflicts; conflicted paths carry stage 1/2/3 records on stdout.
    """
    proc = _run_git(("merge-tree", "--write-tree", "-z", target, source), 300)
    if proc.returncode not in (0, 1):
        detail = proc.stderr.decode("utf-8", "replace").strip() or f"exit {proc.returncode}"
        raise GitError(f"git merge-tree {target} {source}: {detail}")
    parts = proc.stdout.split(b"\0")
    tree = parts[0].decode().strip() if parts and parts[0].strip() else None
    conflicted: set[str] = set()
    for part in parts[1:]:
        match = STAGE_LINE.match(part)
        if match:
            conflicted.add(os.fsdecode(match.group(1)))
    return tree, conflicted


# ---------------------------------------------------------------------- findings


@dataclass
class Finding:
    path: str
    status: str
    side: str = ""
    target_added: int = 0
    branch_added: int = 0
    lost_if_branch_taken: list[str] = field(default_factory=list)
    lost_if_target_kept: list[str] = field(default_factory=list)
    dropped: list[str] = field(default_factory=list)
    takeover: bool = False
    allowed: bool = False
    target_rename: str = ""
    source_rename: str = ""
    identical: bool = False


@dataclass
class Report:
    mode: str
    target: str
    target_commit: str
    source: str
    source_commit: str
    merge_base: str
    findings: list[Finding] = field(default_factory=list)
    conflicted: list[str] = field(default_factory=list)
    overlap: int = 0
    verdict: str = "PASS"
    note: str = ""
    commit: str = ""


def _stale_details(finding: Finding) -> list[str]:
    details: list[str] = []
    if finding.lost_if_branch_taken:
        details.append(
            f"branch copy lacks {len(finding.lost_if_branch_taken)} line(s) "
            f"target added since the merge-base"
        )
    if finding.lost_if_target_kept:
        details.append(
            f"target copy lacks {len(finding.lost_if_target_kept)} line(s) "
            f"the branch added since the merge-base"
        )
    return details


# Statuses that fail the pre-check: one side's copy is the only copy of work the
# other side removed, so no resolution keeps both sides as they stand.
FAILING_STATUSES = (
    "delete-vs-edit",
    "rename/delete",
    "auto-merge-drops",
    "auto-merge-deletes",
)

# Statuses that need a human look even when nothing provably vanishes.
REVIEW_STATUSES = ("conflict", "non-blob", "binary")


def _rename_rename(
    path: str,
    base: str,
    target: str,
    source: str,
    target_dest: str,
    source_dest: str,
    tree: str | None,
    conflicted: set[str],
) -> Finding:
    """Both sides moved the same path — to two new names or to one.

    Two names: git stops with `CONFLICT (rename/rename)` and each copy holds
    work the other lacks, so the report names both destinations. One name: the
    copies may be identical (nothing to lose) or differ; when git merges them
    cleanly the merged copy is checked for an added line that vanished.
    """
    finding = Finding(
        path, "rename/rename", target_rename=target_dest, source_rename=source_dest
    )
    if target_dest != source_dest:
        return finding

    if blob_of(target, target_dest) == blob_of(source, source_dest):
        finding.identical = True
        return finding

    target_added = moved_added_lines(base, target, path, target_dest)
    source_added = moved_added_lines(base, source, path, source_dest)
    finding.target_added = len(target_added)
    finding.branch_added = len(source_added)

    merged = content_of(tree, target_dest) if tree is not None else None
    if merged is not None and not is_binary(merged) and target_dest not in conflicted:
        merged_set = set(text_lines(merged))
        finding.dropped = [
            line for line in target_added + source_added if line not in merged_set
        ]
    if target_dest in conflicted:
        target_copy = set(text_lines(content_of(target, target_dest) or b""))
        source_copy = set(text_lines(content_of(source, source_dest) or b""))
        finding.lost_if_branch_taken = [
            line for line in target_added if line not in source_copy
        ]
        finding.lost_if_target_kept = [
            line for line in source_added if line not in target_copy
        ]
    return finding


def _rename_edit(
    path: str,
    renaming_side: str,
    dest: str,
    target_dest: str,
    source_dest: str,
    base: str,
    target: str,
    source: str,
    tree: str | None,
    conflicted: set[str],
) -> Finding:
    """One side moved the path, the other edited it where it was.

    Git usually follows the rename and carries the edit onto the new name, so
    this shape merges cleanly; calling it a failure would contradict the very
    merge it describes. The verdict therefore comes from the simulated result:
    `dropped` when the moved copy lost a line either side added, REVIEW when
    git stopped on the destination, and nothing to do when the lines arrived.
    """
    renamer = target if renaming_side == "target" else source
    editor = source if renaming_side == "target" else target
    finding = Finding(
        path,
        "rename/edit",
        side=renaming_side,
        target_rename=target_dest,
        source_rename=source_dest,
    )
    moved_added = moved_added_lines(base, renamer, path, dest)
    edited_added = added_lines(base, editor, path)
    if renaming_side == "target":
        finding.target_added, finding.branch_added = len(moved_added), len(edited_added)
    else:
        finding.target_added, finding.branch_added = len(edited_added), len(moved_added)

    merged = content_of(tree, dest) if tree is not None else None
    if merged is not None and not is_binary(merged) and dest not in conflicted:
        merged_set = set(text_lines(merged))
        finding.dropped = [
            line for line in moved_added + edited_added if line not in merged_set
        ]
    return finding


def _gone_from_one_side(
    path: str,
    target_type: str | None,
    source_type: str | None,
    base: str,
    target: str,
    source: str,
    tree: str | None,
    conflicted: set[str],
    target_renames: dict[str, str],
    source_renames: dict[str, str],
) -> Finding:
    """Classify an overlap path that at least one side no longer has.

    `side` is always the side that removed the path — the one that deleted it,
    or the one that renamed it away. `changed_paths()` disables rename detection
    on purpose (a move must not hide the path the other side edited), so a rename
    reaches this function looking like a deletion. Four shapes read alike on that
    listing and must not be reported alike (P2.25 CODE-1):

    - delete/delete    both sides removed it           -> nothing to lose
    - rename/rename    both sides moved it             -> keep both renamed copies
    - rename/delete    one moved it, the other deleted -> the moved copy is the work
    - rename/edit      one moved it, the other edited  -> git follows the move (see _rename_edit)
    """
    target_dest = target_renames.get(path, "")
    source_dest = source_renames.get(path, "")

    if target_type is None and source_type is None:
        if target_dest and source_dest:
            return _rename_rename(
                path, base, target, source, target_dest, source_dest, tree, conflicted
            )
        if target_dest or source_dest:
            return Finding(
                path,
                "rename/delete",
                side="target" if target_dest else "branch",
                target_rename=target_dest,
                source_rename=source_dest,
            )
        return Finding(path, "both-deleted")

    if target_type is None:
        if target_dest:
            return _rename_edit(
                path, "target", target_dest, target_dest, source_dest,
                base, target, source, tree, conflicted,
            )
        return Finding(path, "delete-vs-edit", side="target")
    if source_dest:
        return _rename_edit(
            path, "branch", source_dest, target_dest, source_dest,
            base, target, source, tree, conflicted,
        )
    return Finding(path, "delete-vs-edit", side="branch")


def pre_merge(target_ref: str, source_ref: str) -> Report:
    target = commit_of(target_ref)
    source = commit_of(source_ref)
    base = merge_base(target, source)
    report = Report(
        mode="pre",
        target=target_ref,
        target_commit=target,
        source=source_ref,
        source_commit=source,
        merge_base=base,
    )

    if _is_ancestor(source, target):
        report.note = "source is already contained in the target; nothing to merge"
        return report

    target_paths = set(changed_paths(base, target)) - GENERATED_PATHS
    source_paths = set(changed_paths(base, source)) - GENERATED_PATHS
    overlap = sorted(target_paths & source_paths)
    report.overlap = len(overlap)
    if not overlap:
        report.note = "no file changed on both sides since the merge-base"
        return report

    tree, conflicted = merge_tree(target, source)
    report.conflicted = sorted(conflicted - GENERATED_PATHS)

    target_renames: dict[str, str] | None = None
    source_renames: dict[str, str] | None = None

    for path in overlap:
        target_type = object_type(target, path)
        source_type = object_type(source, path)
        if target_type is None or source_type is None:
            if target_renames is None or source_renames is None:
                target_renames = renames(base, target)
                source_renames = renames(base, source)
            report.findings.append(
                _gone_from_one_side(
                    path,
                    target_type,
                    source_type,
                    base,
                    target,
                    source,
                    tree,
                    conflicted,
                    target_renames,
                    source_renames,
                )
            )
            continue
        if target_type != "blob" or source_type != "blob":
            report.findings.append(Finding(path, "non-blob"))
            continue
        if blob_of(target, path) == blob_of(source, path):
            report.findings.append(Finding(path, "identical"))
            continue

        target_content = content_of(target, path) or b""
        source_content = content_of(source, path) or b""
        if is_binary(target_content) or is_binary(source_content):
            report.findings.append(Finding(path, "binary"))
            continue

        target_added = added_lines(base, target, path)
        source_added = added_lines(base, source, path)
        target_set = set(text_lines(target_content))
        source_set = set(text_lines(source_content))
        finding = Finding(
            path,
            "conflict" if path in conflicted else "auto-merge",
            target_added=len(target_added),
            branch_added=len(source_added),
            lost_if_branch_taken=[line for line in target_added if line not in source_set],
            lost_if_target_kept=[line for line in source_added if line not in target_set],
        )

        if finding.status == "auto-merge" and tree is not None:
            merged = content_of(tree, path)
            if merged is None:
                finding.status = "auto-merge-deletes"
            elif is_binary(merged):
                finding.status = "binary"
            else:
                merged_set = set(text_lines(merged))
                dropped = [
                    line for line in target_added + source_added if line not in merged_set
                ]
                if dropped:
                    finding.status = "auto-merge-drops"
                    finding.dropped = dropped
        report.findings.append(finding)

    if any(
        finding.status in FAILING_STATUSES
        or (finding.status in ("rename/rename", "rename/edit") and finding.dropped)
        for finding in report.findings
    ):
        report.verdict = "FAIL"
    elif report.conflicted or any(
        finding.status in REVIEW_STATUSES
        or (
            finding.status in ("conflict", "rename/rename")
            and (finding.lost_if_branch_taken or finding.lost_if_target_kept)
        )
        for finding in report.findings
    ):
        # A path the simulated merge still conflicts on is never a pass, whatever
        # its per-path status says: git stops there and the producer must look
        # (P2.25 CODE-6). The lost-line lists are evidence for a *choice* — they
        # only mean something on a path whose copies have to be reconciled.
        report.verdict = "REVIEW"
    return report


def _is_ancestor(ancestor: str, descendant: str) -> bool:
    code, _ = git_soft("merge-base", "--is-ancestor", ancestor, descendant)
    return code == 0


def _audit_parents(
    mode: str,
    target_ref: str,
    target_commit: str,
    source_ref: str,
    source_commit: str,
    content: Callable[[str], bytes | None],
    blob: Callable[[str], str | None],
    allowed: set[str],
    skip: frozenset[str] | set[str] = frozenset(),
    commit: str = "",
    renames_from_base: Callable[[str], dict[str, str]] | None = None,
) -> Report:
    """Shared core of --post and --staged: did the result keep both parent deltas?

    Two severities, deliberately asymmetric:

    - `deleted-by-merge` and `takeover` FAIL. A takeover is the P1.16 signature:
      the merge result for a path is *exactly* the other parent's copy of it, so
      one side's delta was replaced wholesale by a stale file. No judgement call
      is involved — the blob id decides.
    - A resolution that keeps a merged blob but supersedes individual added lines
      (two edits of the same line cannot both survive) is reported as `dropped`
      with the lost lines listed, but does not fail. Failing every same-line
      conflict would make the gate unusable and train the producer to ignore it.

    `renames_from_base` maps old -> new path between the merge-base and the
    result. A merge that follows a rename deletes the old path, so without it a
    file that moved would read as `deleted-by-merge` — a false FAIL on a merge
    git resolved correctly (P2.25 CODE-1).
    """
    base = merge_base(target_commit, source_commit)
    report = Report(
        mode=mode,
        target=target_ref,
        target_commit=target_commit,
        source=source_ref,
        source_commit=source_commit,
        merge_base=base,
        commit=commit,
    )

    moved_from_base: dict[str, str] | None = None

    for side_commit, other_commit, side_label, side_key in (
        (target_commit, source_commit, "first parent (target)", "target"),
        (source_commit, target_commit, "second parent (branch)", "branch"),
    ):
        other_blob_by_path = {path: blob_of(other_commit, path) for path in changed_paths(base, side_commit)}
        # A file this side moved is "new" under its new name; diffing the old and
        # new ends together keeps the count to the lines actually added instead of
        # listing the whole moved file as new.
        renamed_from = {new: old for old, new in renames(base, side_commit).items()}
        for path in sorted(other_blob_by_path):
            if path in GENERATED_PATHS or path in skip:
                continue
            origin = renamed_from.get(path, "")
            added = (
                moved_added_lines(base, side_commit, origin, path)
                if origin
                else added_lines(base, side_commit, path)
            )
            if not added:
                continue  # binary/submodule delta: no line evidence either way
            result = content(path)
            moved_to = ""
            if result is None and renames_from_base is not None:
                # A merge that follows a rename deletes the old path: look for
                # the work under its new name before calling this a deletion.
                if moved_from_base is None:
                    moved_from_base = renames_from_base(base)
                moved_to = moved_from_base.get(path, "")
                if moved_to:
                    result = content(moved_to)
            finding = Finding(path, "dropped", side=side_label)
            finding.allowed = path in allowed
            if result is None:
                finding.status = "deleted-by-merge"
                finding.dropped = added
            elif is_binary(result):
                continue
            else:
                result_set = set(text_lines(result))
                dropped = [line for line in added if line not in result_set]
                if not dropped:
                    continue
                finding.dropped = dropped
                if moved_to:
                    if side_key == "target":
                        finding.target_rename = moved_to
                    else:
                        finding.source_rename = moved_to
                else:
                    result_blob = blob(path)
                    finding.takeover = (
                        result_blob is not None and result_blob == other_blob_by_path[path]
                    )
            report.findings.append(finding)

    if any(
        (finding.takeover or finding.status == "deleted-by-merge") and not finding.allowed
        for finding in report.findings
    ):
        report.verdict = "FAIL"
    return report


def merge_head() -> str:
    """The commit a stopped merge is merging (`MERGE_HEAD`), or "" when none is."""
    code, out = git_soft("rev-parse", "--verify", "--quiet", "MERGE_HEAD")
    return out.decode().strip() if code == 0 and out.strip() else ""


def post_merge(commit_ref: str, allowed: set[str]) -> Report:
    resolved = commit_of(commit_ref)
    if merge_head() and resolved == commit_of("HEAD"):
        # HEAD is still the pre-merge commit, so an audit of it says nothing
        # about the merge the producer thinks they are checking.
        raise GitError(
            "a merge is stopped and HEAD is still its pre-merge commit; audit the "
            "index with --staged, or commit the merge and re-run --post"
        )
    code, out = git_soft("rev-list", "--parents", "-n", "1", resolved)
    if code != 0:
        raise GitError(f"cannot read parents of {commit_ref}")
    fields = out.decode().strip().split()
    if len(fields) != 3:
        raise GitError(f"{commit_ref} is not a merge commit (parents: {len(fields) - 1})")
    first_parent, second_parent = fields[1], fields[2]

    def content(path: str) -> bytes | None:
        return content_of(resolved, path)

    def blob(path: str) -> str | None:
        return blob_of(resolved, path)

    return _audit_parents(
        "post",
        f"{commit_ref}^1",
        first_parent,
        f"{commit_ref}^2",
        second_parent,
        content,
        blob,
        allowed,
        commit=resolved,
        renames_from_base=lambda base: renames(base, resolved),
    )


def staged_merge(allowed: set[str]) -> Report:
    """Audit the index of a merge in progress (after `git add`, before commit)."""
    head = commit_of("HEAD")
    other = merge_head()
    if not other:
        raise GitError("no merge in progress: MERGE_HEAD is absent (start `git merge` first)")

    # ls-files -u lists one record per stage; the path is after the tab.
    unresolved = {
        os.fsdecode(record.split(b"\t", 1)[1])
        for record in git("ls-files", "-u", "-z").split(b"\0")
        if b"\t" in record
    }

    def content(path: str) -> bytes | None:
        code, out = git_soft("show", f":{path}")
        return out if code == 0 else None

    def blob(path: str) -> str | None:
        code, out = git_soft("rev-parse", "--verify", "--quiet", f":{path}")
        return out.decode().strip() if code == 0 and out.strip() else None

    report = _audit_parents(
        "staged",
        "HEAD",
        head,
        "MERGE_HEAD",
        other,
        content,
        blob,
        allowed,
        skip=unresolved,
        renames_from_base=index_renames,
    )
    for path in sorted(unresolved):
        report.findings.append(Finding(path, "unresolved", side="index", allowed=path in allowed))
    if any(finding.status == "unresolved" and not finding.allowed for finding in report.findings):
        report.verdict = "FAIL"
    return report


# ------------------------------------------------------------------------ output


def _short(oid: str) -> str:
    return oid[:7] if oid else "?"


def _examples(lines: list[str]) -> None:
    for line in lines[:MAX_EXAMPLES]:
        text = line.strip()
        print(f"      - {text[:MAX_EXAMPLE_CHARS]}{'…' if len(text) > MAX_EXAMPLE_CHARS else ''}")
    if len(lines) > MAX_EXAMPLES:
        print(f"      ... {len(lines) - MAX_EXAMPLES} more")


def render(report: Report) -> None:
    if report.mode == "pre":
        print(
            f"merge-check: pre-merge — target {report.target} ({_short(report.target_commit)}) "
            f"← source {report.source} ({_short(report.source_commit)})"
        )
    else:
        print(
            f"merge-check: {report.mode}-merge audit — {report.target} "
            f"({_short(report.target_commit)}) vs {report.source} "
            f"({_short(report.source_commit)})"
        )
    if report.commit:
        # The evidence has to name the exact tree it audited: a pasted report is
        # worthless if the ref it was run against can move (P2.25 CODE-3).
        print(f"commit {report.commit}")
    print(f"merge-base {_short(report.merge_base)}")
    if report.note:
        print(f"note: {report.note}")
    if report.mode == "pre" and report.overlap:
        print(
            f"{report.overlap} file(s) changed on both sides · "
            f"{len(report.conflicted)} conflicted path(s)"
        )
    print()

    risk = [f for f in report.findings if f.status not in ("identical", "auto-merge")]
    quiet = len(report.findings) - len(risk)
    for finding in risk:
        tag = "STALE-COPY" if finding.takeover else finding.status.upper()
        if finding.allowed:
            tag += " (allowed)"
        counts = ""
        if (
            report.mode == "pre"
            and finding.status not in ("delete-vs-edit", "both-deleted", "rename/delete")
            and (finding.target_added or finding.branch_added)
        ):
            counts = f"  target +{finding.target_added} / branch +{finding.branch_added}"
        print(f"  {tag:<22} {finding.path}{counts}")
        if finding.status == "delete-vs-edit":
            # `side` is the side that deleted; the other one holds the only copy
            # of the work, so it is the copy the resolution has to keep.
            kept = "branch" if finding.side == "target" else "target"
            print(
                f"      the {finding.side} deleted this file; the {kept} side changed it "
                f"— keep the {kept} copy"
            )
        elif finding.status == "both-deleted":
            print("      both sides deleted this path; the merge deletes it too and loses nothing")
        elif finding.status == "rename/rename":
            if finding.target_rename == finding.source_rename:
                dest = finding.target_rename
                if finding.identical:
                    print(
                        f"      both sides renamed this path to {dest} with identical "
                        f"content — nothing to lose"
                    )
                elif finding.dropped or dest in report.conflicted:
                    print(
                        f"      both sides renamed this path to {dest} with different "
                        f"content — reconcile the two copies by hand"
                    )
                else:
                    print(
                        f"      both sides renamed this path to {dest} with different "
                        f"content; the merge kept every line — nothing is lost"
                    )
            else:
                print(
                    f"      the target renamed this path to {finding.target_rename}; "
                    f"the branch renamed it to {finding.source_rename}"
                )
                print("      both renamed copies hold work — keep both files")
        elif finding.status == "rename/delete":
            dest = finding.target_rename or finding.source_rename
            deleter = "branch" if finding.side == "target" else "target"
            print(
                f"      the {finding.side} renamed this file to {dest}; the {deleter} "
                f"deleted it — keep {dest}"
            )
        elif finding.status == "rename/edit":
            dest = finding.target_rename or finding.source_rename
            editor = "branch" if finding.side == "target" else "target"
            if finding.dropped:
                print(
                    f"      the {finding.side} renamed this file to {dest}; the merged copy "
                    f"there drops {len(finding.dropped)} line(s) one side added:"
                )
                _examples(finding.dropped)
            elif dest in report.conflicted:
                print(
                    f"      the {finding.side} renamed this file to {dest}, but git cannot "
                    f"carry the {editor} side's lines over — port them by hand"
                )
            else:
                print(
                    f"      the {finding.side} renamed this file to {dest}; git carried the "
                    f"{editor} side's lines over — nothing is lost"
                )
        for detail in _stale_details(finding):
            print(f"      {detail}")
        if finding.takeover:
            print(
                f"      the merge result is the other parent's copy verbatim: "
                f"{len(finding.dropped)} line(s) from its {finding.side} are gone"
            )
            _examples(finding.dropped)
        elif finding.status == "deleted-by-merge":
            print(
                f"      the merge deleted this file, dropping {len(finding.dropped)} "
                f"line(s) its {finding.side} added:"
            )
            _examples(finding.dropped)
        elif finding.status == "auto-merge-drops" and finding.dropped:
            print(
                f"      the clean merge result silently drops {len(finding.dropped)} "
                f"line(s) that one side added:"
            )
            _examples(finding.dropped)
        elif finding.status == "rename/rename" and finding.dropped:
            print(
                f"      the clean rename merge silently drops {len(finding.dropped)} "
                f"line(s) that a side added:"
            )
            _examples(finding.dropped)
        elif finding.dropped and finding.status != "rename/edit":
            moved_to = finding.target_rename or finding.source_rename
            if moved_to:
                print(
                    f"      the merge kept this file under a new name ({moved_to}) but dropped "
                    f"{len(finding.dropped)} line(s) its {finding.side} added:"
                )
            else:
                print(
                    f"      the resolution supersedes {len(finding.dropped)} line(s) this "
                    f"parent added ({finding.side}); verify that was intended:"
                )
            _examples(finding.dropped)
        if finding.lost_if_branch_taken and finding.status in ("conflict", "rename/rename"):
            print("      taking the branch copy would delete:")
            _examples(finding.lost_if_branch_taken)
        if finding.lost_if_target_kept and finding.status in ("conflict", "rename/rename"):
            print("      keeping the target copy would delete:")
            _examples(finding.lost_if_target_kept)
        if finding.status in ("non-blob", "binary"):
            print("      line comparison is not possible; review this path by hand")

    if quiet:
        lead = "\n" if risk else ""
        print(f"{lead}  ({quiet} other file(s) changed identically or auto-merge cleanly — no risk)")

    print()
    if report.verdict == "PASS":
        print("VERDICT: PASS")
        return
    if report.mode == "pre":
        if report.verdict == "FAIL":
            print("VERDICT: FAIL — this merge cannot preserve both sides as-is; inspect the files above.")
        else:
            print("VERDICT: REVIEW — resolve the files above by hand and keep both sides.")
        print("  Then prove it: python3 tools/merge_check.py --post HEAD")
    else:
        print("VERDICT: FAIL — the merge dropped work that a parent gained since the merge-base.")
        print("  Undo it (`git reset --hard ORIG_HEAD` before any further commits), redo the")
        print("  resolution keeping both sides, and re-run this check.")


def as_json(report: Report) -> str:
    payload = {
        "mode": report.mode,
        "target": report.target,
        "target_commit": report.target_commit,
        "source": report.source,
        "source_commit": report.source_commit,
        "merge_base": report.merge_base,
        "commit": report.commit,
        "verdict": report.verdict,
        "note": report.note,
        "overlap": report.overlap,
        "conflicted": report.conflicted,
        "findings": [
            {
                "path": finding.path,
                "status": finding.status,
                "side": finding.side,
                "allowed": finding.allowed,
                "target_added": finding.target_added,
                "branch_added": finding.branch_added,
                "lost_if_branch_taken": finding.lost_if_branch_taken,
                "lost_if_target_kept": finding.lost_if_target_kept,
                "dropped": finding.dropped,
                "takeover": finding.takeover,
                "target_rename": finding.target_rename,
                "source_rename": finding.source_rename,
                "identical": finding.identical,
            }
            for finding in report.findings
            if finding.status != "identical"
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False)


# ------------------------------------------------------------------------- allow


ALLOW_MAGIC = frozenset("*?[]\\")


def _allow_path(raw: str) -> str:
    """Validate one --allow argument and return it as an exact repo path.

    `--allow` is a whitelist: it turns a blocking finding into a note. An entry
    that is a pattern, an absolute path or a `..` escape would acknowledge paths
    nobody read, and a generated file is already outside the audit. Everything
    the check cannot vouch for is refused here, before the audit runs.
    """
    path = raw.strip()
    if not path:
        raise GitError("--allow needs a repo-relative path")
    if path.startswith("/") or os.path.isabs(path):
        raise GitError(f"--allow takes a repo-relative path, not {raw!r}")
    magic = "".join(sorted(set(path) & ALLOW_MAGIC))
    if magic:
        raise GitError(
            f"--allow takes an exact path, not the pattern {raw!r}: {magic} would "
            f"acknowledge every path it matches"
        )
    parts = path.split("/")
    if ".." in parts:
        raise GitError(f"--allow cannot point outside the repository: {raw!r}")
    if any(part in ("", ".") for part in parts):
        raise GitError(f"--allow takes a normalised path, not {raw!r}")
    if path in GENERATED_PATHS:
        raise GitError(
            f"--allow cannot acknowledge {path}: track.py regenerates it and the "
            f"audit already skips it"
        )
    return path


def _check_allows(report: Report, allowed: set[str]) -> None:
    """Hold every --allow to a finding it is allowed to acknowledge.

    Three ways an acknowledgment can lie: it names no finding (the typo reads as
    "reviewed"), it names the P1.16 stale-copy takeover (the one shape the tool
    decides by blob id, not judgement), or it names a path still unresolved in
    the index (nothing was resolved to acknowledge).
    """
    matched = {finding.path for finding in report.findings if finding.allowed}
    unused = sorted(allowed - matched)
    if unused:
        raise GitError(
            "--allow matched no finding for "
            + ", ".join(unused)
            + " — an acknowledgment that acknowledges nothing hides a typo"
        )
    takeovers = sorted(f.path for f in report.findings if f.allowed and f.takeover)
    if takeovers:
        raise GitError(
            "--allow cannot acknowledge a stale-copy takeover (the P1.16 shape): "
            + ", ".join(takeovers)
            + " — undo the merge and keep both sides"
        )
    unresolved = sorted(
        f.path for f in report.findings if f.allowed and f.status == "unresolved"
    )
    if unresolved:
        raise GitError(
            "--allow cannot acknowledge an unresolved conflict: "
            + ", ".join(unresolved)
            + " — git add the resolution first"
        )


# --------------------------------------------------------------------------- main


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Merge-hygiene gate: flag a merge that would replace newer work with a stale copy.",
        epilog=__doc__.split("Usage:", 1)[1].split("Design notes:", 1)[0]
        if "Usage:" in __doc__
        else None,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("source", nargs="?", help="branch/ref to merge into the target")
    parser.add_argument(
        "--target",
        default="HEAD",
        help="target ref the source merges into (default: HEAD)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--post", metavar="COMMIT", help="audit a completed merge commit")
    mode.add_argument(
        "--staged",
        action="store_true",
        help="audit the index of a merge in progress (HEAD vs MERGE_HEAD)",
    )
    parser.add_argument(
        "--allow",
        action="append",
        default=[],
        metavar="PATH",
        help="--post/--staged only: acknowledge findings for PATH after inspecting them (repeatable)",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.post:
            if args.source:
                parser.error("--post audits a commit; drop the positional source")
            allowed = {_allow_path(raw) for raw in args.allow}
            report = post_merge(args.post, allowed)
            _check_allows(report, allowed)
        elif args.staged:
            if args.source:
                parser.error("--staged audits the index; drop the positional source")
            allowed = {_allow_path(raw) for raw in args.allow}
            report = staged_merge(allowed)
            _check_allows(report, allowed)
        else:
            if not args.source:
                parser.error("give the branch to merge (or use --post/--staged)")
            if args.allow:
                parser.error("--allow acknowledges a completed resolution; use it with --post or --staged")
            report = pre_merge(args.target, args.source)
    except GitError as exc:
        print(f"merge-check: {exc}", file=sys.stderr)
        return EXIT_ERROR

    if args.json:
        print(as_json(report))
    else:
        render(report)
    return EXIT_OK if report.verdict == "PASS" else EXIT_ATTENTION


if __name__ == "__main__":
    sys.exit(main())
