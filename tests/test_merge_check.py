"""Merge-hygiene gate tests (P2.25).

The synthetic repository reproduces the P1.16 incident in miniature:

- `main` gains two test functions and a 25-frame settle loop in
  `game/tests/DateSceneTest.gd` (P1.16's approved work).
- `task/P1.21` forked *before* that and edits the same regions for its own
  reasons (its VRAM test replaces the capture settle).
- The real merge `50752b7` resolved the conflict by keeping the branch copy,
  silently deleting main's two tests.

`tools/merge_check.py` must warn about that resolution before the merge and
fail the post-merge audit, while a merge that keeps both sides stays green.
All repositories are built in tmp_path; nothing here needs the project history
(CI checks out shallow, so an assertion on `50752b7` would be unrunnable).
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
CHECK = ROOT / "tools" / "merge_check.py"

TEST_FILE = "game/tests/DateSceneTest.gd"
STATE_FILE = "production/state.json"

BASE_FILE = """\
extends GdUnitTestSuite


func test_date_scene_wires_character() -> void:
	assert_bool(true).is_true()


func test_capture_screenshots_for_handoff() -> void:
	await get_tree().process_frame


func test_pause_request_propagation() -> void:
	assert_bool(true).is_true()
"""

# main's side: the 25-frame settle plus the two tests P1.16 approved.
MAIN_FILE = """\
extends GdUnitTestSuite


func test_date_scene_wires_character() -> void:
	assert_bool(true).is_true()


func test_capture_screenshots_for_handoff() -> void:
	# Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
	for i: int in 25:
		await get_tree().process_frame


func test_pause_request_propagation() -> void:
	assert_bool(true).is_true()


func test_photosensitive_wiring() -> void:
	_date.set_photosensitive(true)
	assert_bool(_date.photosensitive).is_true()


func test_ambience_forwarding() -> void:
	assert_str(String(_date.get_scenario().get("ambience", ""))).is_equal("cafe")
"""

# the branch's side: its own settle count and its VRAM test, no P1.16 tests.
BRANCH_FILE = """\
extends GdUnitTestSuite


func test_date_scene_wires_character() -> void:
	assert_bool(true).is_true()


func test_capture_screenshots_for_handoff() -> void:
	for i: int in 10:
		await get_tree().process_frame


func test_pause_request_propagation() -> void:
	assert_bool(true).is_true()


func test_vram_usage_budget_under_800mb() -> void:
	var vram_bytes: int = 1
	assert_int(vram_bytes).is_less(800 * 1024 * 1024)
"""

# what a correct manual resolution looks like: both sides kept.
MERGED_FILE = """\
extends GdUnitTestSuite


func test_date_scene_wires_character() -> void:
	assert_bool(true).is_true()


func test_capture_screenshots_for_handoff() -> void:
	# Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
	for i: int in 25:
		await get_tree().process_frame


func test_pause_request_propagation() -> void:
	assert_bool(true).is_true()


func test_photosensitive_wiring() -> void:
	_date.set_photosensitive(true)
	assert_bool(_date.photosensitive).is_true()


func test_ambience_forwarding() -> void:
	assert_str(String(_date.get_scenario().get("ambience", ""))).is_equal("cafe")


func test_vram_usage_budget_under_800mb() -> void:
	var vram_bytes: int = 1
	assert_int(vram_bytes).is_less(800 * 1024 * 1024)
"""


# A file long enough for git's default 50% similarity threshold to pair a move
# with a one-line edit. README.md is a single line, so moving it and adding two
# lines drops below the threshold and git reports delete+add instead of a rename.
MOVE_FILE = "docs/notes.md"
MOVE_TEXT = """\
line one
line two
line three
line four
line five
line six
line seven
line eight
"""


def git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", *args], cwd=repo, capture_output=True, text=True, timeout=120
    )
    assert proc.returncode == 0, f"git {' '.join(args)} failed:\n{proc.stderr}"
    return proc.stdout


def git_expect_failure(repo: Path, *args: str) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        ["git", *args], cwd=repo, capture_output=True, text=True, timeout=120
    )
    assert proc.returncode != 0, f"git {' '.join(args)} unexpectedly succeeded"
    return proc


def check(
    repo: Path, *args: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CHECK), *args],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=120,
        env=env,
    )


def check_json(repo: Path, *args: str) -> tuple[subprocess.CompletedProcess, dict]:
    proc = check(repo, "--json", *args)
    try:
        return proc, json.loads(proc.stdout)
    except json.JSONDecodeError:  # pragma: no cover - surface the failure verbatim
        pytest.fail(f"merge_check emitted non-JSON:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")


def write(repo: Path, path: str, text: str) -> None:
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def commit(repo: Path, message: str) -> None:
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """The P1.16 shape: main has newer work in a file the branch also edited."""
    root = tmp_path / "repo"
    root.mkdir()
    git(root, "init", "-q", "-b", "main")
    git(root, "config", "user.email", "merge-check@example.test")
    git(root, "config", "user.name", "merge check tests")
    git(root, "config", "commit.gpgsign", "false")

    write(root, TEST_FILE, BASE_FILE)
    write(root, "README.md", "leila\n")
    write(root, MOVE_FILE, MOVE_TEXT)
    commit(root, "base")

    # The branch forks here, before P1.16 lands.
    git(root, "checkout", "-q", "-b", "task/P1.21")
    write(root, TEST_FILE, BRANCH_FILE)
    commit(root, "P1.21: VRAM test and its own settle count")

    # main gains P1.16's approved work on the same file.
    git(root, "checkout", "-q", "main")
    write(root, TEST_FILE, MAIN_FILE)
    commit(root, "P1.16: photosensitive/ambience tests and 25-frame settle")

    return root


def merge_expect_conflict(repo: Path, branch: str = "task/P1.21") -> subprocess.CompletedProcess:
    return git_expect_failure(repo, "merge", "--no-ff", "-m", f"merge {branch}", branch)


def resolve_with_branch_copy(repo: Path, path: str) -> None:
    git(repo, "checkout", "--theirs", "--", path)
    git(repo, "add", "--", path)


def commit_merge(repo: Path) -> None:
    git(repo, "commit", "-q", "--no-edit")


def merge_that_deletes_an_extended_handoff(repo: Path) -> str:
    """The E34a shape: a modify/delete resolution takes the deletion, losing added work."""
    path = "production/handoffs/P1.14.md"
    write(repo, path, "# Handoff\n\napproved work\n")
    commit(repo, "handoff v1")

    git(repo, "checkout", "-q", "-b", "keeps-handoff")
    write(repo, path, "# Handoff\n\napproved work\n\nmore approved work\n")
    commit(repo, "handoff v2")

    git(repo, "checkout", "-q", "main")
    git(repo, "rm", "-q", path)
    commit(repo, "drop handoff")

    git_expect_failure(repo, "merge", "--no-ff", "-m", "merge keeps-handoff", "keeps-handoff")
    # resolve modify/delete by accepting the deletion, as the real merges did
    git(repo, "rm", "-q", path)
    commit_merge(repo)
    return path


# --------------------------------------------------------------------------- pre


def test_pre_flags_a_branch_copy_that_lacks_newer_target_work(repo: Path) -> None:
    proc, report = check_json(repo, "task/P1.21")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "REVIEW"
    assert TEST_FILE in report["conflicted"]

    finding = next(item for item in report["findings"] if item["path"] == TEST_FILE)
    assert finding["status"] == "conflict"
    assert "func test_photosensitive_wiring() -> void:" in finding["lost_if_branch_taken"]
    assert "func test_ambience_forwarding() -> void:" in finding["lost_if_branch_taken"]
    assert "func test_vram_usage_budget_under_800mb() -> void:" in finding["lost_if_target_kept"]

    # the human report names the loss, not just the conflict
    text = check(repo, "task/P1.21").stdout
    assert "taking the branch copy would delete:" in text
    assert "func test_photosensitive_wiring() -> void:" in text
    assert "VERDICT: REVIEW" in text

def test_pre_passes_when_the_sides_touch_different_files(repo: Path) -> None:
    git(repo, "checkout", "-q", "-b", "docs-only", "main")
    write(repo, "README.md", "leila\n\nP2 notes\n")
    commit(repo, "docs: notes")
    git(repo, "checkout", "-q", "main")

    proc, report = check_json(repo, "docs-only")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    assert report["overlap"] == 0


def test_pre_passes_when_both_sides_make_the_same_change(repo: Path) -> None:
    git(repo, "checkout", "-q", "-b", "same-change", "main")
    write(repo, "README.md", "leila\n\nshared line\n")
    commit(repo, "same line")

    git(repo, "checkout", "-q", "main")
    write(repo, "README.md", "leila\n\nshared line\n")
    commit(repo, "same line on main")

    proc, report = check_json(repo, "same-change")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    assert report["overlap"] == 1


def test_pre_flags_delete_versus_edit(repo: Path) -> None:
    git(repo, "checkout", "-q", "-b", "deletes-readme", "main")
    git(repo, "rm", "-q", "README.md")
    commit(repo, "drop README")

    git(repo, "checkout", "-q", "main")
    write(repo, "README.md", "leila\n\nmain still edits this\n")
    commit(repo, "edit README")

    proc, report = check_json(repo, "deletes-readme")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "FAIL"
    finding = next(item for item in report["findings"] if item["path"] == "README.md")
    assert finding["status"] == "delete-vs-edit"
    assert finding["side"] == "branch"

    # the report must name the side that still holds the work, not the side that left
    text = check(repo, "deletes-readme").stdout
    assert "the branch deleted this file; the target side changed it" in text
    assert "keep the target copy" in text


def test_pre_names_the_side_that_kept_the_file(repo: Path) -> None:
    """The mirror direction: the target deletes, the branch edits — keep the branch copy."""
    git(repo, "checkout", "-q", "-b", "edits-readme", "main")
    write(repo, "README.md", "leila\n\nbranch still edits this\n")
    commit(repo, "edit README on the branch")

    git(repo, "checkout", "-q", "main")
    git(repo, "rm", "-q", "README.md")
    commit(repo, "drop README on main")

    proc, report = check_json(repo, "edits-readme")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == "README.md")
    assert finding["status"] == "delete-vs-edit"
    assert finding["side"] == "target"

    text = check(repo, "edits-readme").stdout
    assert "the target deleted this file; the branch side changed it" in text
    assert "keep the branch copy" in text


def test_pre_passes_when_both_sides_delete_the_same_file(repo: Path) -> None:
    """Nothing can be lost: both sides deleted the path, so git merges it by deleting."""
    git(repo, "checkout", "-q", "-b", "deletes-readme", "main")
    git(repo, "rm", "-q", "README.md")
    commit(repo, "drop README on the branch")

    git(repo, "checkout", "-q", "main")
    git(repo, "rm", "-q", "README.md")
    commit(repo, "drop README on main")

    proc, report = check_json(repo, "deletes-readme")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    finding = next(item for item in report["findings"] if item["path"] == "README.md")
    assert finding["status"] == "both-deleted"

    # the printed report explains why the overlap is not a risk
    assert "BOTH-DELETED" in check(repo, "deletes-readme").stdout

    # and the habit agrees end to end: this merge is clean and stays clean after it
    git(repo, "merge", "--no-ff", "-m", "merge deletes-readme", "deletes-readme")
    proc, report = check_json(repo, "--post", "HEAD")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"


def test_pre_flags_both_sides_renaming_to_different_names(repo: Path) -> None:
    """A move on each side is not a delete/delete: both copies hold work (CODE-1)."""
    git(repo, "checkout", "-q", "-b", "moves-notes", "main")
    git(repo, "mv", MOVE_FILE, "docs/branch-notes.md")
    commit(repo, "branch renames the notes")

    git(repo, "checkout", "-q", "main")
    git(repo, "mv", MOVE_FILE, "docs/main-notes.md")
    commit(repo, "main renames the notes")

    proc, report = check_json(repo, "moves-notes")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "REVIEW"
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["status"] == "rename/rename"
    assert finding["target_rename"] == "docs/main-notes.md"
    assert finding["source_rename"] == "docs/branch-notes.md"

    text = check(repo, "moves-notes").stdout
    assert "RENAME/RENAME" in text
    assert "BOTH-DELETED" not in text
    assert "docs/main-notes.md" in text
    assert "docs/branch-notes.md" in text

    # the same shape stops the real merge, so REVIEW is the honest verdict
    conflicted = merge_expect_conflict(repo, "moves-notes")
    assert "CONFLICT (rename/rename)" in conflicted.stdout + conflicted.stderr
    git(repo, "merge", "--abort")


def test_pre_flags_a_rename_to_the_same_name_with_both_sides_modified(repo: Path) -> None:
    """Both sides moved a file to one name and edited it — a rename, not a delete."""
    moved = "docs/shared-notes.md"
    git(repo, "checkout", "-q", "-b", "moves-notes", "main")
    git(repo, "mv", MOVE_FILE, moved)
    write(repo, moved, MOVE_TEXT.replace("line four", "branch four"))
    commit(repo, "branch renames and edits the notes")

    git(repo, "checkout", "-q", "main")
    git(repo, "mv", MOVE_FILE, moved)
    write(repo, moved, MOVE_TEXT.replace("line four", "main four"))
    commit(repo, "main renames and edits the notes")

    proc, report = check_json(repo, "moves-notes")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "REVIEW"
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["status"] == "rename/rename"
    assert finding["target_rename"] == finding["source_rename"] == moved
    assert finding["identical"] is False

    text = check(repo, "moves-notes").stdout
    assert "RENAME/RENAME" in text
    assert f"both sides renamed this path to {moved} with different content" in text
    assert "BOTH-DELETED" not in text


def test_pre_names_the_renamed_copy_that_survives(repo: Path) -> None:
    """One side moved the file, the other deleted it: the moved copy is the work."""
    moved = "docs/renamed-notes.md"
    git(repo, "checkout", "-q", "-b", "renames-notes", "main")
    git(repo, "mv", MOVE_FILE, moved)
    write(repo, moved, MOVE_TEXT + "branch work\n")
    commit(repo, "branch renames the notes")

    git(repo, "checkout", "-q", "main")
    git(repo, "rm", "-q", MOVE_FILE)
    commit(repo, "main drops the notes")

    proc, report = check_json(repo, "renames-notes")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "FAIL"
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["status"] == "rename/delete"
    assert finding["side"] == "branch"
    assert finding["source_rename"] == moved

    text = check(repo, "renames-notes").stdout
    assert "RENAME/DELETE" in text
    assert (
        f"the branch renamed this file to {moved}; the target deleted it — keep {moved}"
        in text
    )


def test_pre_passes_when_git_carries_an_edit_onto_a_renamed_file(repo: Path) -> None:
    """A move on one side and an edit on the other merges cleanly; the gate agrees."""
    moved = "docs/moved-notes.md"
    git(repo, "checkout", "-q", "-b", "edits-notes", "main")
    write(repo, MOVE_FILE, MOVE_TEXT.replace("line four", "branch four"))
    commit(repo, "branch edits the notes")

    git(repo, "checkout", "-q", "main")
    git(repo, "mv", MOVE_FILE, moved)
    commit(repo, "main renames the notes")

    proc, report = check_json(repo, "edits-notes")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["status"] == "rename/edit"
    assert finding["dropped"] == []

    text = check(repo, "edits-notes").stdout
    assert "git carried the branch side's lines over" in text

    git(repo, "merge", "--no-ff", "-m", "merge edits-notes", "edits-notes")
    assert "branch four" in (repo / moved).read_text(encoding="utf-8")

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"


# -------------------------------------------------------------------------- post


def test_post_catches_the_p1_16_resolution(repo: Path) -> None:
    """The real incident: resolving the conflict with the branch copy loses main's tests."""
    merge_expect_conflict(repo)
    resolve_with_branch_copy(repo, TEST_FILE)
    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "FAIL"
    finding = next(item for item in report["findings"] if item["path"] == TEST_FILE)
    assert finding["status"] == "dropped"
    assert finding["takeover"] is True
    assert finding["side"] == "first parent (target)"
    assert "func test_photosensitive_wiring() -> void:" in finding["dropped"]
    assert "func test_ambience_forwarding() -> void:" in finding["dropped"]

    text = check(repo, "--post", "HEAD").stdout
    assert "STALE-COPY" in text
    assert "VERDICT: FAIL" in text


def test_post_passes_when_the_resolution_keeps_both_sides(repo: Path) -> None:
    merge_expect_conflict(repo)
    write(repo, TEST_FILE, MERGED_FILE)
    git(repo, "add", "--", TEST_FILE)
    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    # One same-line conflict was necessarily superseded (the branch's settle loop
    # lost to main's 25-frame loop). It is reported, but it is not a stale-copy
    # takeover, so it does not fail the gate.
    warnings = [item for item in report["findings"] if item["path"] == TEST_FILE]
    assert warnings and warnings[0]["takeover"] is False
    assert "\tfor i: int in 10:" in warnings[0]["dropped"]


def test_post_catches_a_merge_that_drops_an_entire_file(repo: Path) -> None:
    """The E34a shape: a modify/delete resolution takes the deletion, losing added work."""
    path = merge_that_deletes_an_extended_handoff(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == path)
    assert finding["status"] == "deleted-by-merge"
    assert "more approved work" in finding["dropped"]


def test_post_follows_a_rename_and_catches_taking_the_deletion(repo: Path) -> None:
    """The moved copy is the work: keeping it passes, deleting it fails, same merge."""
    moved = "docs/renamed-notes.md"
    git(repo, "checkout", "-q", "-b", "renames-notes", "main")
    git(repo, "mv", MOVE_FILE, moved)
    write(repo, moved, MOVE_TEXT + "branch work\n")
    commit(repo, "branch renames the notes")

    git(repo, "checkout", "-q", "main")
    git(repo, "rm", "-q", MOVE_FILE)
    commit(repo, "main drops the notes")

    # resolution that keeps the moved copy: nothing was lost
    merge_expect_conflict(repo, "renames-notes")
    git(repo, "add", moved)
    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"

    # resolution that takes the deletion: the branch's line is gone
    git(repo, "reset", "-q", "--hard", "HEAD^")
    merge_expect_conflict(repo, "renames-notes")
    git(repo, "rm", "-q", "--cached", moved)
    (repo / moved).unlink()
    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == moved)
    assert finding["status"] == "deleted-by-merge"
    assert finding["dropped"] == ["branch work"]


def test_post_catches_a_lossy_resolution_of_a_renamed_file(repo: Path) -> None:
    """A move does not hide the P1.16 shape: one parent's copy verbatim loses the other's line."""
    moved = "docs/moved-notes.md"

    # direction 1 — the branch moves the file, the target edits it in place.
    git(repo, "checkout", "-q", "-b", "moves-notes", "main")
    git(repo, "mv", MOVE_FILE, moved)
    write(repo, moved, MOVE_TEXT + "branch work\n")
    commit(repo, "branch renames the notes")

    git(repo, "checkout", "-q", "main")
    write(repo, MOVE_FILE, MOVE_TEXT + "target work\n")
    commit(repo, "target edits the notes in place")

    merge_expect_conflict(repo, "moves-notes")
    resolve_with_branch_copy(repo, moved)

    proc, report = check_json(repo, "--staged")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["takeover"] is True
    assert finding["dropped"] == ["target work"]
    assert finding["target_rename"] == moved

    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["takeover"] is True
    text = check(repo, "--post", "HEAD").stdout
    assert "STALE-COPY" in text
    assert f"the merge result at {moved} is the other parent's copy verbatim" in text

    # direction 2 — the target moves the file, the branch edits it in place.
    git(repo, "reset", "-q", "--hard", "HEAD^1")
    renamed = "docs/renamed-notes.md"

    git(repo, "checkout", "-q", "-b", "edits-notes", "main")
    write(repo, MOVE_FILE, MOVE_TEXT + "target work\nbranch work\n")
    commit(repo, "branch edits the notes in place")

    git(repo, "checkout", "-q", "main")
    git(repo, "mv", MOVE_FILE, renamed)
    write(repo, renamed, MOVE_TEXT + "target work\ntarget work 2\n")
    commit(repo, "target renames the notes")

    merge_expect_conflict(repo, "edits-notes")
    git(repo, "checkout", "--ours", "--", renamed)
    git(repo, "add", "--", renamed)

    proc, report = check_json(repo, "--staged")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    finding = next(item for item in report["findings"] if item["path"] == MOVE_FILE)
    assert finding["takeover"] is True
    assert finding["dropped"] == ["branch work"]
    assert finding["source_rename"] == renamed
    text = check(repo, "--staged").stdout
    assert "STALE-COPY" in text
    assert f"the merge result at {renamed} is the other parent's copy verbatim" in text

    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "FAIL"


def test_post_names_the_commit_it_audited(repo: Path) -> None:
    """Evidence has to name the tree it audited, not just the ref it ran against."""
    merge_expect_conflict(repo)
    write(repo, TEST_FILE, MERGED_FILE)
    git(repo, "add", "--", TEST_FILE)
    commit_merge(repo)
    head = git(repo, "rev-parse", "HEAD").strip()

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["commit"] == head
    assert f"commit {head}" in check(repo, "--post", "HEAD").stdout


def test_post_refuses_head_while_a_merge_is_stopped(repo: Path) -> None:
    """HEAD is still the pre-merge commit then, so auditing it proves nothing."""
    merge_expect_conflict(repo)

    proc = check(repo, "--post", "HEAD")

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "a merge is stopped" in proc.stderr
    assert "--staged" in proc.stderr

    write(repo, TEST_FILE, MERGED_FILE)
    git(repo, "add", "--", TEST_FILE)
    commit_merge(repo)

    assert check(repo, "--post", "HEAD").returncode == 0


def test_post_allows_a_reviewed_finding(repo: Path) -> None:
    """--allow is the documented escape hatch: a reviewed deletion turns into a note."""
    path = merge_that_deletes_an_extended_handoff(repo)

    proc, report = check_json(repo, "--post", "HEAD", "--allow", path)

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    finding = next(item for item in report["findings"] if item["path"] == path)
    assert finding["status"] == "deleted-by-merge"
    assert finding["allowed"] is True

    text = check(repo, "--post", "HEAD", "--allow", path).stdout
    assert "DELETED-BY-MERGE (allowed)" in text


def test_allow_takes_exact_paths_not_patterns(repo: Path) -> None:
    """A pattern would acknowledge every path it matches, so it is refused."""
    path = merge_that_deletes_an_extended_handoff(repo)

    for pattern in ("production/*", "*", "README.md?"):
        proc = check(repo, "--post", "HEAD", "--allow", pattern)

        assert proc.returncode == 2, proc.stdout + proc.stderr
        assert "takes an exact path" in proc.stderr
        assert "would acknowledge every path it matches" in proc.stderr

    # the exact path is still accepted
    assert check(repo, "--post", "HEAD", "--allow", path).returncode == 0


def test_allow_refuses_paths_outside_the_repository(repo: Path) -> None:
    merge_that_deletes_an_extended_handoff(repo)

    absolute = check(repo, "--post", "HEAD", "--allow", "/etc/passwd")

    assert absolute.returncode == 2, absolute.stdout + absolute.stderr
    assert "repo-relative path" in absolute.stderr

    traversal = check(repo, "--post", "HEAD", "--allow", "../outside.md")

    assert traversal.returncode == 2, traversal.stdout + traversal.stderr
    assert "outside the repository" in traversal.stderr


def test_allow_cannot_acknowledge_a_track_generated_file(repo: Path) -> None:
    merge_that_deletes_an_extended_handoff(repo)

    proc = check(repo, "--post", "HEAD", "--allow", STATE_FILE)

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "track.py regenerates it" in proc.stderr


def test_allow_must_match_a_finding(repo: Path) -> None:
    """A typo must not read as 'reviewed'."""
    merge_that_deletes_an_extended_handoff(repo)

    proc = check(repo, "--post", "HEAD", "--allow", "production/handoffs/P9.99.md")

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "matched no finding" in proc.stderr


def test_allow_cannot_acknowledge_a_stale_copy(repo: Path) -> None:
    """The P1.16 signature is decided by blob id; it is never a reviewed deletion."""
    merge_expect_conflict(repo)
    resolve_with_branch_copy(repo, TEST_FILE)
    commit_merge(repo)

    proc = check(repo, "--post", "HEAD", "--allow", TEST_FILE)

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "stale-copy takeover" in proc.stderr


def test_allow_cannot_acknowledge_an_unresolved_conflict(repo: Path) -> None:
    merge_expect_conflict(repo)

    proc = check(repo, "--staged", "--allow", TEST_FILE)

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "unresolved conflict" in proc.stderr

    git(repo, "merge", "--abort")


def test_pre_rejects_allow(repo: Path) -> None:
    """In pre mode nothing is resolved yet, so there is nothing to acknowledge."""
    proc = check(repo, "--allow", "README.md", "task/P1.21")

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "--allow acknowledges a completed resolution" in proc.stderr


def test_post_ignores_track_generated_files(repo: Path) -> None:
    """state.json/STATUS.md are regenerated by track.py; their merge content proves nothing."""
    write(repo, STATE_FILE, '{\n  "phase": "P2"\n}\n')
    commit(repo, "state: add")

    git(repo, "checkout", "-q", "-b", "task/P1.21-state", "main")
    write(repo, STATE_FILE, '{\n  "phase": "P2",\n  "branch": 1\n}\n')
    commit(repo, "branch state")

    git(repo, "checkout", "-q", "main")
    write(repo, STATE_FILE, '{\n  "phase": "P2",\n  "target": 2\n}\n')
    commit(repo, "target state")

    merge_expect_conflict(repo, "task/P1.21-state")
    resolve_with_branch_copy(repo, STATE_FILE)
    commit_merge(repo)

    proc, report = check_json(repo, "--post", "HEAD")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    assert not [item for item in report["findings"] if item["path"] == STATE_FILE]


def test_post_rejects_a_non_merge_commit(repo: Path) -> None:
    proc = check(repo, "--post", "HEAD")

    assert proc.returncode == 2
    assert "not a merge commit" in proc.stderr


# ------------------------------------------------------------------------ staged


def test_staged_catches_the_bad_resolution_before_the_commit_exists(repo: Path) -> None:
    merge_expect_conflict(repo)
    resolve_with_branch_copy(repo, TEST_FILE)

    proc, report = check_json(repo, "--staged")

    assert proc.returncode == 1, proc.stdout + proc.stderr
    assert report["verdict"] == "FAIL"
    finding = next(item for item in report["findings"] if item["path"] == TEST_FILE)
    assert "func test_photosensitive_wiring() -> void:" in finding["dropped"]
    assert "func test_ambience_forwarding() -> void:" in finding["dropped"]

    git(repo, "merge", "--abort")


def test_staged_passes_when_the_index_keeps_both_sides(repo: Path) -> None:
    merge_expect_conflict(repo)
    write(repo, TEST_FILE, MERGED_FILE)
    git(repo, "add", "--", TEST_FILE)

    proc, report = check_json(repo, "--staged")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"

    git(repo, "merge", "--abort")


def test_staged_flags_unresolved_conflicts(repo: Path) -> None:
    merge_expect_conflict(repo)

    proc, report = check_json(repo, "--staged")

    assert proc.returncode == 1
    statuses = {item["path"]: item["status"] for item in report["findings"]}
    assert statuses.get(TEST_FILE) == "unresolved"

    git(repo, "merge", "--abort")


# ------------------------------------------------------------------- robustness


def test_missing_source_ref_is_an_error_not_a_pass(repo: Path) -> None:
    proc = check(repo, "no-such-branch")

    assert proc.returncode == 2
    assert "not a commit" in proc.stderr


def test_source_already_merged_is_a_pass(repo: Path) -> None:
    merge_expect_conflict(repo)
    write(repo, TEST_FILE, MERGED_FILE)
    git(repo, "add", "--", TEST_FILE)
    commit_merge(repo)

    proc, report = check_json(repo, "task/P1.21")

    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert report["verdict"] == "PASS"
    assert "already contained" in report["note"]


def test_git_missing_from_path_exits_two(repo: Path, tmp_path: Path) -> None:
    """A check that cannot run is exit 2, never a traceback that reads like lost work."""
    nogit = tmp_path / "no-git-on-path"
    nogit.mkdir()

    proc = check(repo, "--post", "HEAD", env={**os.environ, "PATH": str(nogit)})

    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert "git is not installed" in proc.stderr
    assert "Traceback" not in proc.stderr


def load_merge_check():
    """Import the tool so one call can be driven without a fake git binary."""
    spec = importlib.util.spec_from_file_location("merge_check_under_test", CHECK)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_git_timeout_is_an_error_not_a_traceback(monkeypatch: pytest.MonkeyPatch) -> None:
    module = load_merge_check()

    def timed_out(*args: object, **kwargs: object) -> None:
        raise subprocess.TimeoutExpired(cmd="git", timeout=1)

    monkeypatch.setattr(module.subprocess, "run", timed_out)

    with pytest.raises(module.GitError, match="timed out"):
        module.git("status", timeout=1)
    with pytest.raises(module.GitError, match="timed out"):
        module.git_soft("status", timeout=1)
    assert module.main(["--post", "HEAD"]) == module.EXIT_ERROR
