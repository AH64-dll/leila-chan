#!/usr/bin/env python3
"""Leila-chan production tracker.

The plan (tasks) lives in the task tables of production/phases/P*.md.
The state (status, agents, reviews, history) lives in production/state.json.
Progress is always computed from those two files; nobody types a percentage by hand.

Only the producer runs the mutating commands (start, set, review, gate, brief).
Stdlib only. Run from anywhere:  python production/tools/track.py <command> ...
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows consoles default to cp1252

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROD = ROOT / "production"
CONFIG = json.loads((PROD / "config.json").read_text(encoding="utf-8"))
STATE_PATH = PROD / "state.json"

SIZES = CONFIG["sizes"]
ROLES = CONFIG["roles"]
REVIEW_KINDS = {k: v for k, v in CONFIG["reviews"].items() if k != "gate"}
PHASES = CONFIG["phases"]
PHASE_IDS = [p["id"] for p in PHASES]

STATUSES = ["todo", "in_progress", "in_review", "changes_requested", "blocked", "done"]
TRANSITIONS = {
    "todo": {"in_progress", "blocked"},
    "in_progress": {"in_review", "blocked", "todo"},
    "in_review": {"changes_requested", "done", "blocked"},
    "changes_requested": {"in_progress", "blocked"},
    "blocked": {"todo", "in_progress"},
    "done": {"in_progress"},  # reopen, e.g. after a gate audit finds a missed defect
}
VERDICTS = {"approved", "changes", "blocked"}
TASK_ID = re.compile(r"^P\d+\.[A-Z]?\d{2}$")
COLUMNS = ["id", "task", "role", "size", "deps", "review", "refs", "acceptance"]

# validate() issue kinds — severity is carried by this tag, never by the message text
ERR, MISSING_REF = "error", "missing_ref"

# Review recording: a verdict may also be recorded while a task sits in
# changes_requested/blocked, so a parallel review kind of the same round is not
# lost (P1.26). Status effects are monotonic — a late approval never clears a
# prior rejection and the round is never bumped from here.
REVIEWABLE = {"in_review", "changes_requested", "blocked"}
STATUS_RANK = {"in_review": 0, "changes_requested": 1, "blocked": 2}
VERDICT_STATUS = {"approved": "in_review", "changes": "changes_requested", "blocked": "blocked"}

# Self-declared backend metadata: "- Reviewer backend: X" in a review/gate
# report (it may share the line with a date, as the gate template does), and
# "## Round N  (<date>, agent: X)" in a handoff. Names are open-ended (swe2,
# deepseek, claude, devin-native, commandcode, human, …) — never match against a
# fixed list. An appended section such as "## Round 1 — independent verification
# (agent: …)" is not an implementer declaration and must not override round 1.
BACKEND_RE = re.compile(r"Reviewer backend\s*:\s*`?([A-Za-z0-9_.\-]+)", re.I)
HANDOFF_AGENT_RE = re.compile(r"^#+\s*Round\s+(\d+)\s*\([^)]*?\bagent:\s*`?([A-Za-z0-9_.\-]+)", re.I)

# Audited overrides for backend-identity drift that cannot be corrected in
# state.json (legacy/mixed-backend evidence). See production/backend_audit.json.
AUDIT_PATH = PROD / "backend_audit.json"


# ---------------------------------------------------------------- plan + state

def load_plan() -> dict[str, dict]:
    """Parse every task row (| P1.03 | ... |) from the phase docs, in order."""
    tasks: dict[str, dict] = {}
    for phase in PHASES:
        path = ROOT / phase["doc"]
        if not path.exists():
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not re.match(r"^\|\s*P\d+\.", line):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != len(COLUMNS):
                sys.exit(f"{path.name}:{lineno}: expected {len(COLUMNS)} columns, got {len(cells)}")
            t = dict(zip(COLUMNS, cells))
            t["phase"] = phase["id"]
            t["deps"] = _list(t["deps"])
            t["review"] = _list(t["review"])
            t["refs"] = _list(t["refs"])
            t["source"] = f"{phase['doc']}:{lineno}"
            if t["id"] in tasks:
                sys.exit(f"duplicate task id {t['id']} ({t['source']} and {tasks[t['id']]['source']})")
            tasks[t["id"]] = t
    return tasks


def _list(cell: str) -> list[str]:
    cell = cell.strip()
    if cell in ("", "-", "—"):
        return []
    return [x.strip().strip("`") for x in cell.split(",") if x.strip()]


def load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    return {"phases": {}, "tasks": {}, "history": []}


def save_state(state: dict) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def now() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def task_state(state: dict, tid: str) -> dict:
    return state["tasks"].setdefault(tid, {"status": "todo", "agent": None, "round": 0, "reviews": []})


def phase_status(state: dict, pid: str) -> str:
    return state["phases"].get(pid, {}).get("status", "pending")


def log(state: dict, event: str, ref: str, note: str = "") -> None:
    state["history"].append({"ts": now(), "event": event, "ref": ref, "note": note})


def latest_reviews(ts: dict) -> dict[str, dict]:
    """Most recent review per kind for the current round of work."""
    out: dict[str, dict] = {}
    for r in ts.get("reviews", []):
        out[r["kind"]] = r
    return out


def resolve(path: str, tid: str | None = None) -> pathlib.Path | None:
    """A file may live in the main tree or (before merge) in the task's worktree."""
    candidates = [ROOT / path]
    if tid:
        candidates.append(pathlib.Path(CONFIG["worktree_root"]) / tid / path)
    for c in candidates:
        if c.exists():
            return c
    return None


# ------------------------------------------------------- backend declarations

def declared_backend(path: pathlib.Path) -> str | None:
    """The reviewer backend a report declares in its header, or None for a
    legacy report with no `- Reviewer backend:` line."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    for line in lines[:40]:
        m = BACKEND_RE.search(line)
        if m:
            return m.group(1)
    return None


def handoff_agents(path: pathlib.Path) -> dict[int, str]:
    """Round -> implementer backend declared in `## Round N (…, agent: X)` headers."""
    out: dict[int, str] = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return out
    for line in lines:
        m = HANDOFF_AGENT_RE.match(line)
        if m:
            out[int(m.group(1))] = m.group(2)
    return out


def load_backend_audit() -> dict:
    if AUDIT_PATH.exists():
        return json.loads(AUDIT_PATH.read_text(encoding="utf-8"))
    return {}


def audit_covers(audit: dict, section: str, key: str, recorded, declared) -> bool:
    """A ledger entry blesses a drift only if it cites the exact recorded and
    declared values — a stale entry audits nothing."""
    ent = audit.get(section, {}).get(key)
    return bool(ent) and ent.get("recorded") == recorded and ent.get("declared") == declared


def resolve_reviewer(args, report: pathlib.Path, what: str) -> tuple[str | None, str | None]:
    """Effective reviewer = --reviewer, falling back to the report's declared
    backend. A disagreement needs --backend-override so the divergence is
    recorded instead of silent (gate C6)."""
    declared = declared_backend(report)
    mismatch = args.reviewer and declared and args.reviewer != declared
    if args.backend_override and not mismatch:
        sys.exit("--backend-override only applies when --reviewer differs from the report's declared backend")
    if mismatch and not args.backend_override:
        sys.exit(f"{what} declares reviewer backend '{declared}' but --reviewer is "
                 f"'{args.reviewer}'; pass --backend-override \"<evidence>\" for an audited override")
    return args.reviewer or declared, declared


# ---------------------------------------------------------------- progress

def progress(plan: dict, state: dict) -> dict:
    per_phase = {}
    for p in PHASES:
        ids = [t for t in plan if plan[t]["phase"] == p["id"]]
        total = sum(SIZES[plan[t]["size"]] for t in ids)
        done = sum(SIZES[plan[t]["size"]] for t in ids if task_state(state, t)["status"] == "done")
        review = sum(SIZES[plan[t]["size"]] for t in ids if task_state(state, t)["status"] == "in_review")
        per_phase[p["id"]] = {
            "tasks": len(ids),
            "done_tasks": sum(1 for t in ids if task_state(state, t)["status"] == "done"),
            "pct": (done / total * 100) if total else 0.0,
            "review_pct": (review / total * 100) if total else 0.0,
            "status": phase_status(state, p["id"]),
        }
    project = sum(p["weight"] * per_phase[p["id"]]["pct"] / 100 for p in PHASES)
    return {"phases": per_phase, "project": project}


def bar(pct: float, width: int = 20) -> str:
    filled = round(pct / 100 * width)
    return "█" * filled + "░" * (width - filled)


def ready_tasks(plan: dict, state: dict, phase: str | None) -> list[str]:
    out = []
    for tid, t in plan.items():
        if phase and t["phase"] != phase:
            continue
        st = task_state(state, tid)["status"]
        if st == "changes_requested":
            out.append(tid)
        elif st == "todo" and all(task_state(state, d)["status"] == "done" for d in t["deps"]):
            out.append(tid)
    return out


# ---------------------------------------------------------------- commands

def cmd_validate(args) -> int:
    plan = load_plan()
    state = load_state()
    issues: list[tuple[str, str]] = []  # (kind, message)
    for tid, t in plan.items():
        if not TASK_ID.match(tid):
            issues.append((ERR, f"{tid}: bad id format ({t['source']})"))
        if not tid.startswith(t["phase"] + "."):
            issues.append((ERR, f"{tid}: id does not match its phase {t['phase']}"))
        if t["role"] not in ROLES:
            issues.append((ERR, f"{tid}: unknown role {t['role']!r}"))
        if t["size"] not in SIZES:
            issues.append((ERR, f"{tid}: unknown size {t['size']!r}"))
        if not t["review"]:
            issues.append((ERR, f"{tid}: needs at least one review kind"))
        for k in t["review"]:
            if k not in REVIEW_KINDS:
                issues.append((ERR, f"{tid}: unknown review kind {k!r}"))
        for d in t["deps"]:
            if d not in plan:
                issues.append((ERR, f"{tid}: unknown dependency {d}"))
            elif PHASE_IDS.index(plan[d]["phase"]) > PHASE_IDS.index(t["phase"]):
                issues.append((ERR, f"{tid}: depends on a later phase task {d}"))
        for ref in t["refs"]:
            doc = ref.split("§")[0].strip()
            if doc and not resolve(doc):
                issues.append((MISSING_REF, f"{tid}: ref {ref!r} points to a missing file (ok before P0.01 imports the repo)"))
    # cycles
    seen, stack = set(), set()

    def visit(n):
        if n in stack:
            issues.append((ERR, f"dependency cycle through {n}"))
            return
        if n in seen or n not in plan:
            return
        stack.add(n)
        for d in plan[n]["deps"]:
            visit(d)
        stack.discard(n)
        seen.add(n)

    for n in plan:
        visit(n)
    for tid in state["tasks"]:
        if tid not in plan:
            issues.append((ERR, f"state.json has unknown task {tid}"))
    # backend-identity drift: recorded reviewer/agent vs the backend the
    # report/handoff declares (gate C6). Drift needs an audit — an "override"
    # note recorded at review time, "agent_declared" left by `track.py agent`,
    # or a backend_audit.json ledger entry for legacy evidence. Drift on a done
    # task is final, so --strict rejects it; on an open task it is a warning the
    # producer can still correct before completion.
    audit = load_backend_audit()
    audited: set[tuple[str, str]] = set()
    drift: list[tuple[str, bool]] = []  # (message, task is done)

    def note(tid: str, message: str) -> None:
        drift.append((message, state["tasks"][tid].get("status") == "done"))

    for tid, ts in state["tasks"].items():
        if tid not in plan:
            continue
        for r in ts.get("reviews", []):
            rep = resolve(r.get("report", ""), tid)
            key = f"{tid}/{r.get('kind')}/{r.get('round')}"
            if not rep:
                note(tid, f"{tid}: {r.get('kind')} r{r.get('round')} review report "
                          f"{r.get('report')!r} not found (cannot audit its backend)")
                continue
            dec, rec = declared_backend(rep), r.get("reviewer")
            if dec and dec != rec:
                if r.get("override"):
                    continue
                if audit_covers(audit, "reviews", key, rec, dec):
                    audited.add(("reviews", key))
                    continue
                note(tid, f"{tid}: {r.get('kind')} r{r.get('round')} reviewer recorded as "
                          f"{rec!r} but {r.get('report')} declares {dec!r}")
        hpath = resolve(ts.get("handoff") or f"production/handoffs/{tid}.md", tid)
        if hpath:
            dec = handoff_agents(hpath).get(ts.get("round"))
            rec = ts.get("agent")
            if dec and dec != rec:
                if ts.get("agent_declared") == dec:
                    pass
                elif audit_covers(audit, "agents", tid, rec, dec):
                    audited.add(("agents", tid))
                else:
                    note(tid, f"{tid}: agent recorded as {rec!r} but handoff round "
                              f"{ts.get('round')} declares {dec!r}")
    known = {("reviews", k) for k in audit.get("reviews", {})} | {("agents", k) for k in audit.get("agents", {})}
    for section, key in sorted(known - audited):
        # A worktree's state.json can lag the main tree, so a ledger entry for a
        # task this snapshot has never seen is not stale — it may still apply.
        tid = key.split("/", 1)[0]
        if tid in state["tasks"]:
            note(tid, f"backend_audit.json {section} entry {key!r} has no matching drift "
                      f"(stale — correct the record or drop the entry)")
    warns = [m for kind, m in issues if kind == MISSING_REF]
    drift_msgs = [m for m, _ in drift]
    blocking = [m for m, done in drift if done]
    hard = [m for kind, m in issues if kind == ERR]
    for e in hard:
        print("ERROR " + e)
    for e in (warns if args.verbose or args.strict else warns[:3]):
        print("WARN  " + e)
    if len(warns) > 3 and not (args.verbose or args.strict):
        print(f"WARN  ... {len(warns) - 3} more missing-ref warnings (--verbose to list)")
    for e in drift_msgs:
        print("WARN  " + e)
    summary = (f"{len(plan)} tasks in {len(PHASES)} phases; {len(hard)} error(s), {len(warns)} missing-ref "
               f"warning(s), {len(drift_msgs)} backend-drift warning(s)")
    if drift_msgs:
        summary += " (done-task drift fails --strict; open-task drift is advisory)"
    print(summary)
    return 1 if hard or (warns and args.strict) or (blocking and args.strict) else 0


def cmd_status(args) -> int:
    plan, state = load_plan(), load_state()
    pr = progress(plan, state)
    print(f"{CONFIG['project']}  {bar(pr['project'], 30)}  {pr['project']:.1f}% complete\n")
    for p in PHASES:
        ph = pr["phases"][p["id"]]
        print(f"  {p['id']} {p['name']:<34} w{p['weight']:>3}  {bar(ph['pct'])} {ph['pct']:5.1f}%  "
              f"{ph['done_tasks']:>2}/{ph['tasks']:<2} {ph['status']}")
    phase = args.phase or next((p for p in PHASE_IDS if phase_status(state, p) == "active"), None)
    if phase:
        print(f"\n{phase} tasks:")
        for tid, t in plan.items():
            if t["phase"] != phase:
                continue
            ts = task_state(state, tid)
            revs = " ".join(f"{k}:{r['verdict']}" for k, r in latest_reviews(ts).items())
            print(f"  {tid:<7} {ts['status']:<18} {t['role']:<5} {t['size']}  {t['task'][:58]:<58} {revs}")
    return 0


def cmd_next(args) -> int:
    plan, state = load_plan(), load_state()
    phase = args.phase or next((p for p in PHASE_IDS if phase_status(state, p) == "active"), None)
    if not phase:
        print("No active phase. Start one with: track.py start P0")
        return 1
    ids = ready_tasks(plan, state, phase)
    if not ids:
        print(f"No ready tasks in {phase}.")
        return 0
    by_role: dict[str, list[str]] = {}
    for tid in ids:
        by_role.setdefault(plan[tid]["role"], []).append(tid)
    for role, tids in by_role.items():
        print(f"{role} ({ROLES[role]['name']}):")
        for tid in tids:
            st = task_state(state, tid)["status"]
            flag = "  [REWORK]" if st == "changes_requested" else ""
            print(f"  {tid}  {plan[tid]['size']}  {plan[tid]['task']}{flag}")
    return 0


def cmd_start(args) -> int:
    state = load_state()
    pid = args.phase
    idx = PHASE_IDS.index(pid)
    if idx > 0 and phase_status(state, PHASE_IDS[idx - 1]) != "closed" and not args.force:
        print(f"{PHASE_IDS[idx - 1]} has not passed its gate. Use --force only with the user's approval.")
        return 1
    state["phases"].setdefault(pid, {})
    state["phases"][pid].update({"status": "active", "started": now()})
    log(state, "phase_start", pid, args.note or "")
    save_state(state)
    print(f"{pid} is active.")
    return 0


def cmd_set(args) -> int:
    plan, state = load_plan(), load_state()
    tid, new = args.task, args.status
    if tid not in plan:
        sys.exit(f"unknown task {tid}")
    if new not in STATUSES:
        sys.exit(f"status must be one of {STATUSES}")
    t, ts = plan[tid], task_state(state, tid)
    old = ts["status"]
    if new not in TRANSITIONS[old]:
        sys.exit(f"{tid}: cannot go {old} -> {new}")
    if phase_status(state, t["phase"]) != "active":
        sys.exit(f"{tid}: phase {t['phase']} is not active")
    if new == "in_progress" and old in ("todo", "blocked"):
        undone = [d for d in t["deps"] if task_state(state, d)["status"] != "done"]
        if undone and not args.force:
            sys.exit(f"{tid}: dependencies not done: {', '.join(undone)}")
    if new == "in_progress":
        ts["round"] = ts.get("round", 0) + 1
        if ts["round"] > CONFIG["max_review_rounds"] + 1 and not args.force:
            sys.exit(f"{tid}: over {CONFIG['max_review_rounds']} review rounds - escalate to the user")
        if args.agent:
            ts["agent"] = args.agent
        ts.setdefault("started", now())
    if new == "in_review":
        handoff = f"production/handoffs/{tid}.md"
        hpath = resolve(handoff, tid)
        if not hpath:
            sys.exit(f"{tid}: no handoff report at {handoff} (main tree or worktree)")
        ts["handoff"] = handoff
        declared_agent = handoff_agents(hpath).get(ts["round"])
        if declared_agent and not ts.get("agent"):
            ts["agent"] = declared_agent
            log(state, "agent", tid, f"adopted from handoff: {declared_agent}")
        elif declared_agent and ts["agent"] != declared_agent and not args.force:
            sys.exit(f"{tid}: handoff declares agent '{declared_agent}' but state records "
                     f"'{ts['agent']}'; run `track.py agent {tid} <backend>` to correct, "
                     f"or --force to keep the recorded value")
        elif declared_agent and ts["agent"] != declared_agent:
            ts["agent_declared"] = declared_agent
            log(state, "agent-drift", tid,
                f"handoff declares {declared_agent}; recorded {ts['agent']} kept (--force)")
    if new == "done":
        latest = latest_reviews(ts)
        missing = [k for k in t["review"] if latest.get(k, {}).get("verdict") != "approved"
                   or latest[k].get("round") != ts["round"]]
        if missing:
            sys.exit(f"{tid}: required reviews not approved for round {ts['round']}: {', '.join(missing)}")
        ts["finished"] = now()
    if new == "blocked" and not args.note:
        sys.exit("blocked needs --note explaining the blocker")
    ts["status"] = new
    log(state, f"{old}->{new}", tid, args.note or "")
    save_state(state)
    print(f"{tid}: {old} -> {new}")
    return 0


def cmd_agent(args) -> int:
    """Correct the implementer backend, e.g. after `subagent` fell back from SWE-2 to DeepSeek."""
    plan, state = load_plan(), load_state()
    if args.task not in plan:
        sys.exit(f"unknown task {args.task}")
    ts = task_state(state, args.task)
    old = ts.get("agent")
    ts["agent"] = args.backend
    # Keep the audit trail honest: if the handoff declares a different backend,
    # remember what it claimed so `validate` sees the correction as deliberate.
    hpath = resolve(ts.get("handoff") or f"production/handoffs/{args.task}.md", args.task)
    declared = handoff_agents(hpath).get(ts.get("round", 0)) if hpath else None
    if declared and declared != args.backend:
        ts["agent_declared"] = declared
        print(f"{args.task}: note - handoff round {ts.get('round')} declares agent '{declared}'; "
              f"recorded '{args.backend}' as an audited override")
    else:
        ts.pop("agent_declared", None)
    log(state, "agent", args.task, f"{old} -> {args.backend}")
    save_state(state)
    print(f"{args.task}: implementer backend {old} -> {args.backend}")
    return 0


def cmd_review(args) -> int:
    plan, state = load_plan(), load_state()
    tid, kind, verdict = args.task, args.kind, args.verdict
    if tid not in plan:
        sys.exit(f"unknown task {tid}")
    if kind not in REVIEW_KINDS:
        sys.exit(f"review kind must be one of {list(REVIEW_KINDS)}")
    if verdict not in VERDICTS:
        sys.exit(f"verdict must be one of {sorted(VERDICTS)}")
    ts = task_state(state, tid)
    if ts["status"] not in REVIEWABLE:
        sys.exit(f"{tid} is {ts['status']}, not in_review")
    report = resolve(args.report, tid)
    if not report:
        sys.exit(f"review report not found: {args.report}")
    reviewer, declared = resolve_reviewer(args, report, args.report)
    if reviewer and ts.get("agent") and reviewer == ts["agent"] and not args.allow_same:
        sys.exit(f"reviewer {reviewer} is the implementer's backend; use another backend or --allow-same")
    if ts["status"] != "in_review" and any(r["kind"] == kind and r.get("round") == ts["round"]
                                          for r in ts.get("reviews", [])):
        sys.exit(f"{tid}: {kind} already has a round {ts['round']} verdict; "
                 f"only remaining review kinds can be recorded while {ts['status']}")
    entry = {"kind": kind, "verdict": verdict, "round": ts["round"], "reviewer": reviewer,
             "report": args.report, "ts": now()}
    if declared:
        entry["declared"] = declared
    if args.backend_override:
        entry["override"] = args.backend_override
    ts["reviews"].append(entry)
    log(state, f"review:{kind}:{verdict}", tid, args.report)
    old = ts["status"]
    if STATUS_RANK[VERDICT_STATUS[verdict]] > STATUS_RANK[old]:
        ts["status"] = VERDICT_STATUS[verdict]
        log(state, f"{old}->{ts['status']}", tid, f"by {kind} review")
    save_state(state)
    print(f"{tid}: {kind} review {verdict} (round {ts['round']})")
    return 0


def cmd_gate(args) -> int:
    plan, state = load_plan(), load_state()
    pid = args.phase
    if phase_status(state, pid) != "active":
        sys.exit(f"{pid} is not active")
    report = resolve(args.report)
    if not report:
        sys.exit(f"gate report not found: {args.report}")
    reviewer, declared = resolve_reviewer(args, report, args.report)
    if args.verdict == "pass":
        open_ = [t for t in plan if plan[t]["phase"] == pid and task_state(state, t)["status"] != "done"]
        if open_:
            sys.exit(f"{pid} cannot pass: open tasks {', '.join(open_)}")
        state["phases"][pid].update({"status": "closed", "closed": now(), "gate_report": args.report})
    entry = {"verdict": args.verdict, "report": args.report, "ts": now(), "reviewer": reviewer}
    if declared:
        entry["declared"] = declared
    if args.backend_override:
        entry["override"] = args.backend_override
    state["phases"][pid].setdefault("gates", []).append(entry)
    log(state, f"gate:{args.verdict}", pid, args.report)
    save_state(state)
    print(f"{pid}: gate {args.verdict}")
    return 0


TEMPLATE_VAR = re.compile(r"\{\{(\w+)\}\}")


def fill(template: str, values: dict) -> str:
    return TEMPLATE_VAR.sub(lambda m: str(values.get(m.group(1), m.group(0))), template)


def cmd_brief(args) -> int:
    plan, state = load_plan(), load_state()
    tid = args.task
    if tid not in plan:
        sys.exit(f"unknown task {tid}")
    t, ts = plan[tid], task_state(state, tid)
    inplace = t["role"] == "PROD" or tid in CONFIG.get("inplace_tasks", [])
    wt = ROOT if inplace else pathlib.Path(CONFIG["worktree_root"]) / tid
    # Implement briefs may be written just before or just after `set ... in_progress` bumps the round.
    current = ts.get("round", 0)
    if args.kind:
        rnd = max(current, 1)
    else:
        rnd = current if ts["status"] == "in_progress" else current + 1
    deps = "\n".join(f"- {d} — {plan[d]['task']} (handoff: production/handoffs/{d}.md)" for d in t["deps"]) or "- none"
    prior = [r for r in ts.get("reviews", []) if r["verdict"] != "approved"]
    prior_txt = "\n".join(f"- round {r['round']} {r['kind']} review: {r['report']}" for r in prior) or "- none (first round)"
    values = {
        "task_id": tid, "title": t["task"], "phase": t["phase"],
        "phase_doc": next(p["doc"] for p in PHASES if p["id"] == t["phase"]),
        "role": t["role"], "role_name": ROLES[t["role"]]["name"], "role_skill": ROLES[t["role"]]["skill"],
        "size": t["size"],
        "acceptance": "\n".join(f"- [ ] {c.strip()}" for c in t["acceptance"].split(";") if c.strip()),
        "refs": "\n".join(f"- {r}" for r in t["refs"]) or "- (none listed — use the phase doc)",
        "deps": deps, "reviews": ", ".join(t["review"]), "round": rnd, "prior_reviews": prior_txt,
        "worktree": wt.as_posix(), "branch": "main (in place)" if inplace else f"task/{tid}", "root": ROOT.as_posix(),
        "journal": f"production/journals/{t['phase']}/{t['role']}.md",
        "handoff": f"production/handoffs/{tid}.md",
    }
    if args.kind:
        kind = args.kind
        if kind not in REVIEW_KINDS:
            sys.exit(f"review kind must be one of {list(REVIEW_KINDS)}")
        values.update({"review_kind": kind, "review_name": REVIEW_KINDS[kind]["name"],
                       "review_skill": REVIEW_KINDS[kind]["skill"],
                       "report": f"production/reviews/{tid}-{kind}-r{rnd}.md"})
        template = (PROD / "templates" / "brief_review.md").read_text(encoding="utf-8")
        out = PROD / "briefs" / f"{tid}-review-{kind}-r{rnd}.md"
    else:
        template = (PROD / "templates" / "brief_implement.md").read_text(encoding="utf-8")
        out = PROD / "briefs" / f"{tid}-r{rnd}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(fill(template, values), encoding="utf-8")
    print(out.relative_to(ROOT).as_posix())
    return 0


def cmd_gate_brief(args) -> int:
    plan, state = load_plan(), load_state()
    pid = args.phase
    phase = next(p for p in PHASES if p["id"] == pid)
    n = len(state["phases"].get(pid, {}).get("gates", [])) + 1
    rows = []
    for tid, t in plan.items():
        if t["phase"] != pid:
            continue
        ts = task_state(state, tid)
        reports = ", ".join(r["report"] for r in latest_reviews(ts).values()) or "—"
        rows.append(f"| {tid} | {ts['status']} | {t['role']} | {ts.get('agent') or '—'} | {reports} |")
    values = {"phase": pid, "phase_name": phase["name"], "phase_doc": phase["doc"], "round": n,
              "review_skill": CONFIG["reviews"]["gate"]["skill"], "root": ROOT.as_posix(),
              "report": f"production/gates/{pid}-gate-r{n}.md",
              "task_table": "| Task | Status | Role | Agent | Review reports |\n|---|---|---|---|---|\n" + "\n".join(rows)}
    template = (PROD / "templates" / "brief_gate.md").read_text(encoding="utf-8")
    out = PROD / "briefs" / f"{pid}-gate-r{n}.md"
    out.write_text(fill(template, values), encoding="utf-8")
    print(out.relative_to(ROOT).as_posix())
    return 0


def cmd_render(args) -> int:
    plan, state = load_plan(), load_state()
    pr = progress(plan, state)
    L = [f"# {CONFIG['project']} — production status", "",
         f"_Generated by `python production/tools/track.py render` at {now()}. Do not edit by hand._", "",
         f"## Overall: **{pr['project']:.1f}%**", "", f"`{bar(pr['project'], 40)}`", "",
         "| Phase | Name | Weight | Status | Tasks | Progress | In review |",
         "|---|---|---:|---|---:|---|---:|"]
    for p in PHASES:
        ph = pr["phases"][p["id"]]
        L.append(f"| {p['id']} | [{p['name']}]({p['doc'].removeprefix('production/')}) | {p['weight']}% | "
                 f"{ph['status']} | {ph['done_tasks']}/{ph['tasks']} | `{bar(ph['pct'], 12)}` {ph['pct']:.0f}% | "
                 f"{ph['review_pct']:.0f}% |")
    active = [p for p in PHASE_IDS if phase_status(state, p) == "active"]
    for pid in active:
        L += ["", f"## {pid} task board", "", "| Task | Title | Role | Size | Status | Agent | Round | Reviews |",
              "|---|---|---|---|---|---|---:|---|"]
        for tid, t in plan.items():
            if t["phase"] != pid:
                continue
            ts = task_state(state, tid)
            revs = ", ".join(f"{k}: {r['verdict']}" for k, r in latest_reviews(ts).items()) or "—"
            L.append(f"| {tid} | {t['task']} | {t['role']} | {t['size']} | {ts['status']} | "
                     f"{ts.get('agent') or '—'} | {ts.get('round', 0)} | {revs} |")
        L += ["", f"**Ready now:** {', '.join(ready_tasks(plan, state, pid)) or 'nothing'}"]
    # role workload across the whole project
    L += ["", "## Role workload (open tasks, all phases)", "", "| Role | Name | Open | Done |", "|---|---|---:|---:|"]
    for role, meta in ROLES.items():
        ids = [t for t in plan if plan[t]["role"] == role]
        done = sum(1 for t in ids if task_state(state, t)["status"] == "done")
        L.append(f"| {role} | {meta['name']} | {len(ids) - done} | {done} |")
    blocked = [t for t in plan if task_state(state, t)["status"] == "blocked"]
    if blocked:
        L += ["", "## Blocked", ""]
        last_note = {}
        for h in state["history"]:
            if h["event"].endswith("->blocked"):
                last_note[h["ref"]] = h["note"]
        L += [f"- **{t}** {plan[t]['task']} — {last_note.get(t, '')}" for t in blocked]
    decisions = PROD / "DECISIONS.md"
    if decisions.exists():
        open_d = [l for l in decisions.read_text(encoding="utf-8").splitlines() if l.startswith("| D") and "OPEN" in l]
        L += ["", f"## Open decisions for the user: {len(open_d)}", ""] + open_d[:10]
    L += ["", "## Recent activity", ""]
    L += [f"- {h['ts'][:16]} `{h['ref']}` {h['event']} {h['note']}".rstrip() for h in state["history"][-15:][::-1]] or ["- none yet"]
    (PROD / "STATUS.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"wrote production/STATUS.md ({pr['project']:.1f}%)")
    return 0


def cmd_report(args) -> int:
    plan, state = load_plan(), load_state()
    since = dt.datetime.now().astimezone() - dt.timedelta(days=args.days)
    events = [h for h in state["history"] if dt.datetime.fromisoformat(h["ts"]) >= since]
    done = [h["ref"] for h in events if h["event"].endswith("->done")]
    weight = sum(SIZES[plan[t]["size"]] for t in done if t in plan)
    pr = progress(plan, state)
    print(f"Last {args.days} day(s): {len(done)} task(s) done ({weight} size points); project at {pr['project']:.1f}%")
    for t in done:
        print(f"  done  {t}  {plan[t]['task']}")
    for h in events:
        if h["event"].startswith("review:") and not h["event"].endswith("approved"):
            print(f"  {h['event']}  {h['ref']}  {h['note']}")
        if h["event"].startswith("gate:"):
            print(f"  {h['event']}  {h['ref']}")
    remaining = sum(SIZES[plan[t]["size"]] for t in plan if task_state(state, t)["status"] != "done")
    if weight:
        print(f"Velocity {weight / args.days:.2f} pts/day -> ~{remaining / (weight / args.days):.0f} days of work left at this pace")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("validate", help="check the plan tables and state")
    s.add_argument("--strict", action="store_true",
                   help="fail on missing refs and on backend drift for done tasks")
    s.add_argument("--verbose", action="store_true"); s.set_defaults(fn=cmd_validate)
    s = sub.add_parser("status", help="print progress"); s.add_argument("--phase"); s.set_defaults(fn=cmd_status)
    s = sub.add_parser("next", help="tasks ready to dispatch"); s.add_argument("--phase"); s.set_defaults(fn=cmd_next)
    s = sub.add_parser("start", help="activate a phase"); s.add_argument("phase", choices=PHASE_IDS)
    s.add_argument("--note"); s.add_argument("--force", action="store_true"); s.set_defaults(fn=cmd_start)
    s = sub.add_parser("set", help="change a task status"); s.add_argument("task"); s.add_argument("status")
    s.add_argument("--agent", help="backend that does the work (swe2, deepseek, claude, devin-native, human, …)")
    s.add_argument("--note"); s.add_argument("--force", action="store_true"); s.set_defaults(fn=cmd_set)
    s = sub.add_parser("agent", help="correct the implementer backend of a task"); s.add_argument("task")
    s.add_argument("backend", help="any backend name; audited against the handoff's declared agent")
    s.set_defaults(fn=cmd_agent)
    s = sub.add_parser("review", help="record a review verdict"); s.add_argument("task"); s.add_argument("kind")
    s.add_argument("verdict"); s.add_argument("--report", required=True)
    s.add_argument("--reviewer", help="reviewer backend; defaults to the report's declared 'Reviewer backend:'")
    s.add_argument("--backend-override", help="audit note required when --reviewer differs from the "
                   "report's declared backend (legacy/mixed-backend evidence)")
    s.add_argument("--allow-same", action="store_true"); s.set_defaults(fn=cmd_review)
    s = sub.add_parser("gate", help="record a phase-gate verdict"); s.add_argument("phase", choices=PHASE_IDS)
    s.add_argument("verdict", choices=["pass", "fail"]); s.add_argument("--report", required=True)
    s.add_argument("--reviewer", help="gate reviewer backend; defaults to the report's declared backend")
    s.add_argument("--backend-override", help="audit note when --reviewer differs from the declared backend")
    s.set_defaults(fn=cmd_gate)
    s = sub.add_parser("brief", help="write an implement (or --kind review) brief"); s.add_argument("task")
    s.add_argument("--kind", help="review kind: code | design | content | safety"); s.set_defaults(fn=cmd_brief)
    s = sub.add_parser("gate-brief", help="write a phase-gate review brief"); s.add_argument("phase", choices=PHASE_IDS); s.set_defaults(fn=cmd_gate_brief)
    s = sub.add_parser("render", help="write production/STATUS.md"); s.set_defaults(fn=cmd_render)
    s = sub.add_parser("report", help="activity + velocity report"); s.add_argument("--days", type=int, default=7); s.set_defaults(fn=cmd_report)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
