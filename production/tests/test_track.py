"""Tests for production/tools/track.py (P0.11).

track.py binds itself to its repo root via ``Path(__file__).parents[2]`` and
reads ``production/config.json`` at import time, so the fixture materializes a
minimal production tree inside tmp_path — fixture config, phase docs, the real
brief templates and a copy of track.py — and imports that copy fresh per test.
Commands then run exactly as the real tool runs them (module-level ROOT/CONFIG
derivation included), but every mutation lands in tmp_path, never in the live
state.json.
"""

import importlib.util
import itertools
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
REAL_TRACK = REPO_ROOT / "production" / "tools" / "track.py"
REAL_TEMPLATES = REPO_ROOT / "production" / "templates"


# ---------------------------------------------------------------- fixture tree

def _config(root: Path) -> dict:
    return {
        "project": "Track Fixture",
        "worktree_root": (root / "worktrees").as_posix(),
        "max_review_rounds": 3,
        "inplace_tasks": ["P0.04"],
        "sizes": {"S": 1, "M": 3},
        "phases": [
            {"id": "P0", "name": "Fixture phase zero", "weight": 60, "doc": "production/phases/P0_fixture.md"},
            {"id": "P1", "name": "Fixture phase one", "weight": 40, "doc": "production/phases/P1_fixture.md"},
        ],
        "roles": {
            "PROD": {"name": "Producer", "skill": ".claude/skills/leila-producer/SKILL.md"},
            "REL": {"name": "Build & Release Engineer", "skill": ".claude/skills/role-build-release/SKILL.md"},
            "ENG": {"name": "Engine Architect", "skill": ".claude/skills/role-engine-architect/SKILL.md"},
        },
        "reviews": {
            "code": {"name": "Code review", "skill": ".claude/skills/review-code/SKILL.md"},
            "design": {"name": "Design-fidelity review", "skill": ".claude/skills/review-design-fidelity/SKILL.md"},
            "gate": {"name": "Phase-gate review", "skill": ".claude/skills/review-phase-gate/SKILL.md"},
        },
    }


HEADER = ("| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |\n"
          "|---|---|---|---|---|---|---|---|\n")


def _row(*cells: str) -> str:
    return "| " + " | ".join(cells) + " |\n"


P0_ROWS = [
    _row("P0.01", "First task", "REL", "S", "—", "code", "README.md", "alpha; beta"),
    _row("P0.02", "Second task", "ENG", "S", "P0.01", "code, design", "`README.md§2`", "check it"),
    _row("P0.03", "Producer task", "PROD", "S", "—", "code", "-", "done"),
    _row("P0.04", "In-place REL task", "REL", "M", "P0.02", "design", "README.md", "ok"),
]
P1_ROWS = [
    _row("P1.01", "Later task", "ENG", "S", "P0.02", "code", "README.md", "x"),
]


def write_phase(root: Path, pid: str, rows: list[str]) -> None:
    (root / "production" / "phases" / f"{pid}_fixture.md").write_text(
        f"# {pid} fixture\n\n" + HEADER + "".join(rows), encoding="utf-8")


def build_tree(root: Path) -> Path:
    prod = root / "production"
    (prod / "tools").mkdir(parents=True)
    (prod / "templates").mkdir()
    (prod / "phases").mkdir()
    (prod / "briefs").mkdir()
    shutil.copy(REAL_TRACK, prod / "tools" / "track.py")
    for name in ("brief_implement.md", "brief_review.md", "brief_gate.md"):
        shutil.copy(REAL_TEMPLATES / name, prod / "templates" / name)
    (prod / "config.json").write_text(json.dumps(_config(root), indent=2), encoding="utf-8")
    (root / "README.md").write_text("# fixture\n", encoding="utf-8")
    write_phase(root, "P0", P0_ROWS)
    write_phase(root, "P1", P1_ROWS)
    return root


_COUNTER = itertools.count()


def load_tracker(root: Path):
    """Import the copied track.py fresh; its ROOT/CONFIG derive from the fixture tree."""
    spec = importlib.util.spec_from_file_location(
        f"track_fixture_{next(_COUNTER)}", root / "production" / "tools" / "track.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def base_state(p0: str = "active") -> dict:
    return {"phases": {"P0": {"status": p0}}, "tasks": {}, "history": []}


class Tracker:
    """A track.py module bound to a tmp production tree, with argv/state helpers."""

    def __init__(self, mod, root: Path):
        self.mod = mod
        self.root = root
        self.prod = root / "production"

    def run(self, *argv: str) -> int:
        old = sys.argv
        sys.argv = ["track.py", *argv]
        try:
            return self.mod.main()
        finally:
            sys.argv = old

    def state(self) -> dict:
        return json.loads((self.prod / "state.json").read_text(encoding="utf-8"))

    def write_state(self, state: dict) -> None:
        (self.prod / "state.json").write_text(
            json.dumps(state, indent=2) + "\n", encoding="utf-8")

    @staticmethod
    def task(status: str = "todo", **kw) -> dict:
        ts = {"status": status, "agent": None, "round": 0, "reviews": []}
        ts.update(kw)
        return ts


@pytest.fixture
def tk(tmp_path) -> Tracker:
    root = build_tree(tmp_path)
    return Tracker(load_tracker(root), root)


# ---------------------------------------------------------------- plan + state

def test_load_plan_parses_rows(tk):
    plan = tk.mod.load_plan()
    assert list(plan) == ["P0.01", "P0.02", "P0.03", "P0.04", "P1.01"]
    assert plan["P0.02"]["deps"] == ["P0.01"]
    assert plan["P0.02"]["review"] == ["code", "design"]
    assert plan["P0.02"]["refs"] == ["README.md§2"]      # backticks stripped
    assert plan["P0.03"]["refs"] == []                   # "-" cell -> empty
    assert plan["P0.01"]["phase"] == "P0"
    assert "P0_fixture.md:" in plan["P0.01"]["source"]


def test_load_plan_rejects_short_row(tk):
    write_phase(tk.root, "P0", [_row("P0.01", "x", "REL", "S", "—", "code", "README.md")])
    with pytest.raises(SystemExit, match="expected 8 columns, got 7"):
        tk.mod.load_plan()


def test_load_plan_rejects_duplicate_id(tk):
    write_phase(tk.root, "P0", P0_ROWS + P0_ROWS[:1])
    with pytest.raises(SystemExit, match="duplicate task id P0.01"):
        tk.mod.load_plan()


def test_fill_substitutes_known_vars_only(tk):
    assert tk.mod.fill("{{a}}/{{b}}", {"a": "x"}) == "x/{{b}}"


def test_transitions_cover_every_status(tk):
    assert set(tk.mod.TRANSITIONS) == set(tk.mod.STATUSES)
    for targets in tk.mod.TRANSITIONS.values():
        assert targets <= set(tk.mod.STATUSES)
    assert "in_progress" in tk.mod.TRANSITIONS["done"]    # reopen after a gate audit
    assert "done" not in tk.mod.TRANSITIONS["todo"]       # no skipping review


def test_ready_tasks_returns_actionable_subset(tk):
    st = base_state()
    st["tasks"]["P0.01"] = Tracker.task("done", round=1)
    st["tasks"]["P0.02"] = Tracker.task("changes_requested", round=1)
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    ready = tk.mod.ready_tasks(tk.mod.load_plan(), tk.mod.load_state(), "P0")
    assert ready == ["P0.02"]   # rework first; P0.04 waits on P0.02; P0.03 busy


def test_progress_weights_done_tasks_by_size(tk):
    st = base_state()
    st["tasks"]["P0.04"] = Tracker.task("done")   # M = 3 of P0's 6 size points
    tk.write_state(st)
    pr = tk.mod.progress(tk.mod.load_plan(), tk.mod.load_state())
    assert pr["phases"]["P0"]["pct"] == pytest.approx(50.0)
    assert pr["project"] == pytest.approx(30.0)   # P0 weight 60% * 50%


# ---------------------------------------------------------------- validate

def test_validate_clean_fixture_passes(tk, capsys):
    tk.write_state(base_state())
    assert tk.run("validate", "--strict") == 0
    assert "5 tasks in 2 phases; 0 error(s), 0 missing-ref warning(s)" in capsys.readouterr().out


def _dangling_row(i: int = 9) -> str:
    return _row(f"P0.{i:02d}", "Dangling ref", "REL", "S", "—", "code", f"docs/m{i}.md", "x")


def test_validate_missing_ref_is_a_warning_not_an_error(tk, capsys):
    write_phase(tk.root, "P0", P0_ROWS + [_dangling_row()])
    tk.write_state(base_state())
    assert tk.run("validate") == 0
    out = capsys.readouterr().out
    assert "WARN  P0.09: ref 'docs/m9.md' points to a missing file" in out
    assert "0 error(s), 1 missing-ref warning(s)" in out
    assert "ERROR" not in out


def test_validate_strict_turns_missing_ref_into_failure(tk):
    write_phase(tk.root, "P0", P0_ROWS + [_dangling_row()])
    tk.write_state(base_state())
    assert tk.run("validate", "--strict") == 1


def test_validate_error_text_never_controls_severity(tk, capsys):
    """Regression for the old `"missing file" in e` substring classification:
    a hard error whose message happens to contain that phrase must stay an error."""
    st = base_state()
    st["tasks"]["missing file trap"] = Tracker.task("todo")
    tk.write_state(st)
    assert tk.run("validate") == 1
    out = capsys.readouterr().out
    assert "ERROR state.json has unknown task missing file trap" in out
    assert "1 error(s), 0 missing-ref warning(s)" in out


ERROR_CASES = [
    ([_row("P0.01", "x", "NOPE", "S", "—", "code", "README.md", "a")], "unknown role 'NOPE'"),
    ([_row("P0.01", "x", "REL", "XL", "—", "code", "README.md", "a")], "unknown size 'XL'"),
    ([_row("P0.01", "x", "REL", "S", "P0.99", "code", "README.md", "a")], "unknown dependency P0.99"),
    ([_row("P0.01", "x", "REL", "S", "P1.01", "code", "README.md", "a")], "depends on a later phase task P1.01"),
    ([_row("P0.01", "x", "REL", "S", "—", "bogus", "README.md", "a")], "unknown review kind 'bogus'"),
    ([_row("P0.01", "x", "REL", "S", "—", "-", "README.md", "a")], "needs at least one review kind"),
    ([_row("P1.02", "x", "REL", "S", "—", "code", "README.md", "a")], "id does not match its phase P0"),
    ([_row("P0.1", "x", "REL", "S", "—", "code", "README.md", "a")], "bad id format"),
    ([_row("P0.01", "x", "REL", "S", "P0.02", "code", "README.md", "a"),
      _row("P0.02", "x", "REL", "S", "P0.01", "code", "README.md", "a")], "dependency cycle through P0.0"),
]


@pytest.mark.parametrize("rows,needle", ERROR_CASES)
def test_validate_flags_plan_errors(tk, capsys, rows, needle):
    write_phase(tk.root, "P0", rows)
    tk.write_state(base_state())
    assert tk.run("validate") == 1
    out = capsys.readouterr().out
    assert any(l.startswith("ERROR ") and needle in l for l in out.splitlines())


def test_validate_truncates_missing_ref_warnings(tk, capsys):
    write_phase(tk.root, "P0", P0_ROWS + [_dangling_row(i) for i in range(5, 10)])
    tk.write_state(base_state())
    assert tk.run("validate") == 0
    out = capsys.readouterr().out
    assert "WARN  ... 2 more missing-ref warnings (--verbose to list)" in out
    assert "docs/m9.md" not in out                    # tail warnings hidden
    assert tk.run("validate", "--verbose") == 0       # --verbose lists them all
    out = capsys.readouterr().out
    assert all(f"docs/m{i}.md" in out for i in range(5, 10))


# ---------------------------------------------------------------- set (transitions)

def test_set_in_progress_bumps_round_and_records_agent(tk, capsys):
    tk.write_state(base_state())
    assert tk.run("set", "P0.03", "in_progress", "--agent", "swe2") == 0
    ts = tk.state()["tasks"]["P0.03"]
    assert (ts["status"], ts["round"], ts["agent"]) == ("in_progress", 1, "swe2")
    assert "started" in ts
    assert "P0.03: todo -> in_progress" in capsys.readouterr().out
    assert any(h["event"] == "todo->in_progress" and h["ref"] == "P0.03"
               for h in tk.state()["history"])


@pytest.mark.parametrize("target", ["done", "in_review", "changes_requested"])
def test_set_rejects_illegal_transitions(tk, target):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("todo")
    tk.write_state(st)
    with pytest.raises(SystemExit, match=f"cannot go todo -> {target}"):
        tk.run("set", "P0.03", target)


def test_set_rejects_unknown_task_and_status(tk):
    tk.write_state(base_state())
    with pytest.raises(SystemExit, match="unknown task P9.99"):
        tk.run("set", "P9.99", "in_progress")
    with pytest.raises(SystemExit, match="status must be one of"):
        tk.run("set", "P0.03", "bogus")


def test_set_requires_active_phase(tk):
    st = base_state(p0="pending")
    st["tasks"]["P0.03"] = Tracker.task("todo")
    tk.write_state(st)
    with pytest.raises(SystemExit, match="phase P0 is not active"):
        tk.run("set", "P0.03", "in_progress")


def test_set_in_progress_blocked_by_undone_deps(tk):
    tk.write_state(base_state())
    with pytest.raises(SystemExit, match=r"dependencies not done: P0\.01"):
        tk.run("set", "P0.02", "in_progress")
    assert tk.run("set", "P0.02", "in_progress", "--force") == 0


def test_set_in_progress_once_deps_done(tk):
    st = base_state()
    st["tasks"]["P0.01"] = Tracker.task("done", round=1)
    tk.write_state(st)
    assert tk.run("set", "P0.02", "in_progress") == 0


def _handoff(tk: Tracker, tid: str = "P0.03", worktree: bool = False) -> Path:
    base = tk.root / "worktrees" / tid if worktree else tk.root
    p = base / "production" / "handoffs" / f"{tid}.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("# handoff\n", encoding="utf-8")
    return p


def test_set_in_review_requires_handoff(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    with pytest.raises(SystemExit, match="no handoff report"):
        tk.run("set", "P0.03", "in_review")
    _handoff(tk)
    assert tk.run("set", "P0.03", "in_review") == 0
    assert tk.state()["tasks"]["P0.03"]["handoff"] == "production/handoffs/P0.03.md"


def test_set_in_review_handoff_may_live_in_the_worktree(tk):
    """resolve() also checks worktree_root/<tid>/ so unmerged handoffs count."""
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    _handoff(tk, worktree=True)
    assert tk.run("set", "P0.03", "in_review") == 0


def test_set_done_requires_approved_review_of_the_current_round(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    _handoff(tk)
    report = tk.prod / "reviews" / "P0.03-code-r1.md"
    report.parent.mkdir(exist_ok=True)
    report.write_text("VERDICT: APPROVED\n", encoding="utf-8")
    tk.run("set", "P0.03", "in_review")
    with pytest.raises(SystemExit, match="required reviews not approved for round 1: code"):
        tk.run("set", "P0.03", "done")
    tk.run("review", "P0.03", "code", "approved",
           "--report", "production/reviews/P0.03-code-r1.md", "--reviewer", "deepseek")
    assert tk.run("set", "P0.03", "done") == 0
    ts = tk.state()["tasks"]["P0.03"]
    assert ts["status"] == "done" and "finished" in ts


def test_set_done_rejects_a_review_from_an_earlier_round(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_review", round=2, reviews=[
        {"kind": "code", "verdict": "approved", "round": 1, "reviewer": "deepseek",
         "report": "production/reviews/P0.03-code-r1.md", "ts": "t"}])
    tk.write_state(st)
    with pytest.raises(SystemExit, match="round 2: code"):
        tk.run("set", "P0.03", "done")


def test_set_blocked_requires_a_note(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    with pytest.raises(SystemExit, match="blocked needs --note"):
        tk.run("set", "P0.03", "blocked")
    assert tk.run("set", "P0.03", "blocked", "--note", "waiting on a GPU") == 0


def test_set_done_reopens_to_in_progress(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("done", round=1, finished="t")
    tk.write_state(st)
    assert tk.run("set", "P0.03", "in_progress") == 0
    assert tk.state()["tasks"]["P0.03"]["round"] == 2


def test_set_in_progress_escalates_past_max_review_rounds(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("changes_requested", round=4)  # max = 3
    tk.write_state(st)
    with pytest.raises(SystemExit, match="over 3 review rounds"):
        tk.run("set", "P0.03", "in_progress")
    assert tk.run("set", "P0.03", "in_progress", "--force") == 0


# ---------------------------------------------------------------- review

def _report(tk: Tracker, name: str = "r.md", verdict: str = "VERDICT: APPROVED") -> str:
    p = tk.prod / "reviews" / name
    p.parent.mkdir(exist_ok=True)
    p.write_text(verdict + "\n", encoding="utf-8")
    return f"production/reviews/{name}"


def test_review_changes_sends_task_back(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_review", round=1)
    tk.write_state(st)
    report = _report(tk)
    assert tk.run("review", "P0.03", "code", "changes",
                  "--report", report, "--reviewer", "deepseek") == 0
    ts = tk.state()["tasks"]["P0.03"]
    assert ts["status"] == "changes_requested"
    assert ts["reviews"][0]["kind"] == "code" and ts["reviews"][0]["round"] == 1


def test_review_blocked_marks_task_blocked(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_review", round=1)
    tk.write_state(st)
    report = _report(tk)
    tk.run("review", "P0.03", "code", "blocked", "--report", report)
    assert tk.state()["tasks"]["P0.03"]["status"] == "blocked"


def test_review_requires_in_review_status_and_a_real_report(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_progress", round=1)
    tk.write_state(st)
    with pytest.raises(SystemExit, match="not in_review"):
        tk.run("review", "P0.03", "code", "approved", "--report", "production/reviews/x.md")
    st["tasks"]["P0.03"]["status"] = "in_review"
    tk.write_state(st)
    with pytest.raises(SystemExit, match="review report not found"):
        tk.run("review", "P0.03", "code", "approved", "--report", "production/reviews/x.md")


def test_review_rejects_the_implementers_own_backend(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("in_review", round=1, agent="swe2")
    tk.write_state(st)
    report = _report(tk)
    with pytest.raises(SystemExit, match="implementer's backend"):
        tk.run("review", "P0.03", "code", "approved", "--report", report, "--reviewer", "swe2")
    assert tk.run("review", "P0.03", "code", "approved",
                  "--report", report, "--reviewer", "swe2", "--allow-same") == 0


# ---------------------------------------------------------------- briefs

def test_brief_renders_the_implement_template(tk, capsys):
    st = base_state()
    st["tasks"]["P0.01"] = Tracker.task("done", round=1)
    tk.write_state(st)
    assert tk.run("brief", "P0.02") == 0
    assert capsys.readouterr().out.strip() == "production/briefs/P0.02-r1.md"
    text = (tk.prod / "briefs" / "P0.02-r1.md").read_text(encoding="utf-8")
    assert "{{" not in text                       # every template var got a value
    assert "# Task brief — P0.02: Second task" in text
    assert "Engine Architect" in text and "(ENG)" in text
    assert "working round 1" in text
    assert "- [ ] check it" in text               # acceptance split into checkboxes
    assert "- P0.01 — First task (handoff: production/handoffs/P0.01.md)" in text
    assert f"`{(tk.root / 'worktrees' / 'P0.02').as_posix()}` (git branch `task/P0.02`)" in text
    assert "reviewed by: **code, design**" in text


@pytest.mark.parametrize("status,round_,expected", [
    ("todo", 0, "r1"),               # not started: next round is 1
    ("in_progress", 1, "r1"),        # brief for the running round stays r1
    ("changes_requested", 1, "r2"),  # rework brief is the next round
])
def test_brief_picks_the_right_round(tk, capsys, status, round_, expected):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task(status, round=round_)
    tk.write_state(st)
    assert tk.run("brief", "P0.03") == 0
    assert capsys.readouterr().out.strip() == f"production/briefs/P0.03-{expected}.md"


@pytest.mark.parametrize("tid", ["P0.03", "P0.04"])  # PROD role / inplace_tasks list
def test_brief_inplace_tasks_use_the_main_tree(tk, tid):
    tk.write_state(base_state())
    tk.run("brief", tid)
    text = (tk.prod / "briefs" / f"{tid}-r1.md").read_text(encoding="utf-8")
    assert f"`{tk.root.as_posix()}` (git branch `main (in place)`)" in text


def test_brief_review_kind_writes_a_review_brief(tk, capsys):
    tk.write_state(base_state())
    assert tk.run("brief", "P0.02", "--kind", "code") == 0
    assert capsys.readouterr().out.strip() == "production/briefs/P0.02-review-code-r1.md"
    text = (tk.prod / "briefs" / "P0.02-review-code-r1.md").read_text(encoding="utf-8")
    assert "{{" not in text
    assert "# Review brief — Code review of P0.02: Second task" in text
    assert "production/reviews/P0.02-code-r1.md" in text    # report path for the reviewer


def test_brief_rejects_an_unknown_review_kind(tk):
    tk.write_state(base_state())
    with pytest.raises(SystemExit, match="review kind must be one of"):
        tk.run("brief", "P0.02", "--kind", "bogus")


def test_brief_lists_prior_non_approved_reviews(tk):
    st = base_state()
    st["tasks"]["P0.03"] = Tracker.task("changes_requested", round=1, reviews=[
        {"kind": "code", "verdict": "changes", "round": 1, "reviewer": "deepseek",
         "report": "production/reviews/P0.03-code-r1.md", "ts": "t"},
        {"kind": "design", "verdict": "approved", "round": 1, "reviewer": "deepseek",
         "report": "production/reviews/P0.03-design-r1.md", "ts": "t"},
    ])
    tk.write_state(st)
    tk.run("brief", "P0.03")
    text = (tk.prod / "briefs" / "P0.03-r2.md").read_text(encoding="utf-8")
    assert "- round 1 code review: production/reviews/P0.03-code-r1.md" in text
    assert "P0.03-design-r1.md" not in text   # approved reviews are not rework debt


def test_gate_brief_lists_phase_tasks_and_counts_gates(tk, capsys):
    st = base_state()
    st["tasks"]["P0.01"] = Tracker.task("done", round=1, reviews=[
        {"kind": "code", "verdict": "approved", "round": 1, "reviewer": "deepseek",
         "report": "production/reviews/P0.01-code-r1.md", "ts": "t"}])
    st["tasks"]["P0.02"] = Tracker.task("in_progress", round=1, agent="swe2")
    tk.write_state(st)
    assert tk.run("gate-brief", "P0") == 0
    assert capsys.readouterr().out.strip() == "production/briefs/P0-gate-r1.md"
    text = (tk.prod / "briefs" / "P0-gate-r1.md").read_text(encoding="utf-8")
    assert "{{" not in text
    assert "# Phase-gate brief — P0 Fixture phase zero (gate round 1)" in text
    assert "| P0.01 | done | REL | — | production/reviews/P0.01-code-r1.md |" in text
    assert "| P0.02 | in_progress | ENG | swe2 | — |" in text
    assert "production/gates/P0-gate-r1.md" in text
    # a recorded gate bumps the next brief to round 2
    st["phases"]["P0"]["gates"] = [{"verdict": "fail", "report": "production/gates/P0-gate-r1.md", "ts": "t"}]
    tk.write_state(st)
    tk.run("gate-brief", "P0")
    assert (tk.prod / "briefs" / "P0-gate-r2.md").exists()


# ---------------------------------------------------------------- live repo

def test_the_real_repo_still_validates_strict():
    """End-to-end guard: the same command CI runs, against the live plan + state."""
    proc = subprocess.run([sys.executable, str(REAL_TRACK), "validate", "--strict"],
                          capture_output=True, text=True, cwd=REPO_ROOT)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "0 error(s), 0 missing-ref warning(s)" in proc.stdout
