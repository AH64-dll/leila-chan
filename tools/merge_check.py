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


def git(*args: str, timeout: int = 120) -> bytes:
    """Run git and return stdout; raise GitError with git's own words on failure."""
    try:
        proc = subprocess.run(
            ["git", "--literal-pathspecs", *args],
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:  # pragma: no cover - no git on PATH
        raise GitError("git is not installed") from exc
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace").strip() or f"exit {proc.returncode}"
        raise GitError(f"git {' '.join(args)}: {detail}")
    return proc.stdout


def git_soft(*args: str, timeout: int = 120) -> tuple[int, bytes]:
    """Run git and return (exit code, stdout) without raising; for expected misses."""
    proc = subprocess.run(
        ["git", "--literal-pathspecs", *args],
        capture_output=True,
        timeout=timeout,
    )
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


def added_lines(base: str, tip: str, path: str) -> list[str]:
    """Non-blank lines the tip added to path relative to base.

    Line-based on purpose: it is the unit the producer can act on ("this test
    function is gone"), and it survives whitespace-only churn being ignored.
    """
    out = git("diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, tip, "--", path)
    lines: list[str] = []
    for raw in out.decode("utf-8", "replace").splitlines():
        if raw.startswith("+++") or raw.startswith("---"):
            continue
        if raw.startswith("+") and raw[1:].strip():
            lines.append(raw[1:])
    return lines


def merge_tree(target: str, source: str) -> tuple[str | None, set[str]]:
    """Simulate the merge without touching the worktree.

    Returns (result tree id, conflicted paths). git merge-tree writes the would-be
    tree into the object database (dangling unless referenced) and exits 1 when
    any path conflicts; conflicted paths carry stage 1/2/3 records on stdout.
    """
    try:
        proc = subprocess.run(
            ["git", "merge-tree", "--write-tree", "-z", target, source],
            capture_output=True,
            timeout=300,
        )
    except FileNotFoundError as exc:  # pragma: no cover - no git on PATH
        raise GitError("git is not installed") from exc
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

    for path in overlap:
        target_type = object_type(target, path)
        source_type = object_type(source, path)
        if target_type is None or source_type is None:
            deleted_side = "target" if target_type is None else "branch"
            report.findings.append(Finding(path, "delete-vs-edit", side=deleted_side))
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

    if any(f.status in ("delete-vs-edit", "auto-merge-drops", "auto-merge-deletes") for f in report.findings):
        report.verdict = "FAIL"
    elif any(
        f.status in ("conflict", "non-blob", "binary")
        or f.lost_if_branch_taken
        or f.lost_if_target_kept
        for f in report.findings
    ):
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
    """
    base = merge_base(target_commit, source_commit)
    report = Report(
        mode=mode,
        target=target_ref,
        target_commit=target_commit,
        source=source_ref,
        source_commit=source_commit,
        merge_base=base,
    )

    for side_commit, other_commit, side_label in (
        (target_commit, source_commit, "first parent (target)"),
        (source_commit, target_commit, "second parent (branch)"),
    ):
        other_blob_by_path = {path: blob_of(other_commit, path) for path in changed_paths(base, side_commit)}
        for path in sorted(other_blob_by_path):
            if path in GENERATED_PATHS or path in skip:
                continue
            added = added_lines(base, side_commit, path)
            if not added:
                continue  # binary/submodule delta: no line evidence either way
            result = content(path)
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


def post_merge(commit_ref: str, allowed: set[str]) -> Report:
    resolved = commit_of(commit_ref)
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
    )


def staged_merge(allowed: set[str]) -> Report:
    """Audit the index of a merge in progress (after `git add`, before commit)."""
    head = commit_of("HEAD")
    code, out = git_soft("rev-parse", "--verify", "--quiet", "MERGE_HEAD")
    if code != 0 or not out.strip():
        raise GitError("no merge in progress: MERGE_HEAD is absent (start `git merge` first)")
    other = out.decode().strip()

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
        "staged", "HEAD", head, "MERGE_HEAD", other, content, blob, allowed, skip=unresolved
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
        if report.mode == "pre":
            counts = f"  target +{finding.target_added} / branch +{finding.branch_added}"
        print(f"  {tag:<22} {finding.path}{counts}")
        if finding.status == "delete-vs-edit":
            keeps = "target" if finding.side == "target" else "branch"
            print(f"      the {finding.side} deleted this file; the {keeps} side changed it")
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
        elif finding.dropped:
            print(
                f"      the resolution supersedes {len(finding.dropped)} line(s) this "
                f"parent added ({finding.side}); verify that was intended:"
            )
            _examples(finding.dropped)
        if finding.lost_if_branch_taken and finding.status == "conflict":
            print("      taking the branch copy would delete:")
            _examples(finding.lost_if_branch_taken)
        if finding.lost_if_target_kept and finding.status == "conflict":
            print("      keeping the target copy would delete:")
            _examples(finding.lost_if_target_kept)
        if finding.status in ("non-blob", "binary"):
            print("      line comparison is not possible; review this path by hand")

    if risk and quiet:
        print(f"\n  ({quiet} other file(s) changed identically or auto-merge cleanly — no risk)")

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
            }
            for finding in report.findings
            if finding.status != "identical"
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False)


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
            report = post_merge(args.post, set(args.allow))
        elif args.staged:
            if args.source:
                parser.error("--staged audits the index; drop the positional source")
            report = staged_merge(set(args.allow))
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
