#!/usr/bin/env python3
"""Prompt lab runner (P1.20; dose-aware in P2.21).

One command, from the repo/worktree root:
    python tools/promptlab/run.py
Writes results JSON incrementally to tools/promptlab/results/ (re-runnable:
turns already present in the results file are skipped, so Ctrl-C is cheap).
Normally driven by plan.py, which starts one llama-server per scheduled dose.

The dose is a llama-server **launch** flag (`--control-vector-scaled`, docs/06
§4), so it is an input to the run, not a per-request parameter: `--dose` is
recorded in meta and on every row, and a resumed file refuses to mix doses.

Then score + report:
    python tools/promptlab/score.py  tools/promptlab/results/<file>.json
    python tools/promptlab/report.py tools/promptlab/results/<file>.json
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab


def _rel(p):
    """Repo-relative path for committed metadata; a bare name outside the repo."""
    path = Path(p)
    try:
        return path.resolve().relative_to(lab.ROOT).as_posix()
    except Exception:
        return path.name


def _system_sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def _case_prompt_sha(case):
    return _system_sha(lab.system_prompt(case["stage"], case["path"], case["runner_up"],
                                         case["scene"], case["memories"], case["events"],
                                         lab.offered_values(case["stage"],
                                                            case.get("offered_actions", ())),
                                         None))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default=lab.DEFAULT_URL)
    p.add_argument("--sets", nargs="*", default=None,
                   help="set files under tools/promptlab/sets/ (default: all stage_*.jsonl)")
    p.add_argument("--runs", type=int, default=2, help="runs per case (default 2)")
    p.add_argument("--out", default=None, help="results JSON path (default results/<date>_v2.json)")
    p.add_argument("--only", nargs="*", default=None, help="run only these case ids")
    p.add_argument("--max-cases", type=int, default=None)
    p.add_argument("--timeout", type=int, default=900)
    p.add_argument("--order", default="docs", choices=sorted(lab.ORDER_ALIASES),
                   help="wire schema order: docs = shipped (default); the rest are DCR candidates")
    p.add_argument("--dose", type=float, default=None,
                   help="steering dose the server was launched with (docs/02 §9); recorded")
    p.add_argument("--exercise", default=None,
                   help="plan exercise id (e.g. sched_s3 / dose12), recorded for the report")
    p.add_argument("--plan", default=None, help="plan file name, recorded for the report")
    p.add_argument("--player-name", default=lab.PLAYER_NAME)
    a = p.parse_args()

    set_paths = [Path(s) if Path(s).is_absolute() else lab.SETS_DIR / s
                 for s in (a.sets or [p for p in sorted(lab.SETS_DIR.glob("stage_*.jsonl"))])]
    cases = []
    for sp in set_paths:
        cases += lab.load_set(sp)

    suffix = "" if a.order == "docs" else f"_{a.order}"
    out_path = Path(a.out) if a.out else lab.RESULTS_DIR / f"{time.strftime('%Y-%m-%d')}{suffix}_v2.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if out_path.exists():
        doc = json.loads(out_path.read_text(encoding="utf-8"))
        recorded_order = doc["meta"].get("order", "docs")
        if recorded_order != a.order:
            raise SystemExit(f"{out_path.name} holds order={recorded_order!r}, refusing to mix "
                             f"order={a.order!r} results (pass --out)")
        recorded_dose = doc["meta"].get("dose")
        if recorded_dose != a.dose:
            raise SystemExit(f"{out_path.name} holds dose={recorded_dose!r}, refusing to mix "
                             f"dose={a.dose!r} results (pass --out)")
        done = {(r["id"], r["run"]) for r in doc["results"]}
        print(f"resuming: {len(done)} turns already in {out_path.name}")
    else:
        props = lab.server_props(a.url)
        raw_model = props.get("model_path") or props.get("model_alias") or "?"
        doc = {"meta": {"task": "P2.21 prompt lab v2",
                        "date": time.strftime("%Y-%m-%d %H:%M"),
                        "plan": a.plan,
                        "exercise": a.exercise,
                        "url": a.url,
                        "model": f"models/{Path(raw_model).name}" if raw_model != "?" else "?",
                        "model_ftype": props.get("model_ftype"),
                        "build_info": props.get("build_info"),
                        "dose": a.dose,
                        "dose_note": ("steering dose is a llama-server launch flag "
                                      "(--control-vector-scaled, docs/06 §4); recorded per row"),
                        "sampling": lab.SAMPLING,
                        "order": a.order,
                        "schema_property_order": lab.resolve_order(a.order),
                        "player_name": a.player_name,
                        "sets": [_rel(s) for s in set_paths],
                        "runs_per_case": a.runs},
               "results": []}
        done = set()

    n_total = sum(a.runs for c in cases if not a.only or c["id"] in a.only)
    if a.only and n_total == 0:
        raise SystemExit(f"run.py: --only matched no case in {[_rel(s) for s in set_paths]} "
                         f"(known ids: {[c['id'] for c in cases][:6]}…)")
    if a.max_cases:
        n_total = min(n_total, a.max_cases * a.runs)
    n_done = 0
    for case in cases:
        if a.only and case["id"] not in a.only:
            continue
        prompt_sha = _case_prompt_sha(case)
        for run_i in range(1, a.runs + 1):
            if (case["id"], run_i) in done:
                n_done += 1
                continue
            if a.max_cases and n_done >= a.max_cases * a.runs:
                break
            offered_actions = list(case.get("offered_actions", []))
            offered = lab.offered_values(case["stage"], offered_actions)
            rec = {"id": case["id"], "stage": case["stage"], "path": case["path"],
                   "runner_up": case["runner_up"], "run": run_i,
                   "msg": case["msg"], "near_fewshot": case["near_fewshot"],
                   "read_ok": case["read_ok"], "feelings_ok": case["feelings_ok"],
                   "dose": a.dose, "exercise": a.exercise,
                   "offered_actions": offered_actions,
                   "events": len(case["events"]),
                   "system_sha": prompt_sha,
                   "history_turns": len(case.get("history", [])),
                   "memories": len(case.get("memories", []))}
            try:
                raw, lat, usage = lab.post_turn(
                    a.url, case["stage"], case["msg"],
                    player_name=a.player_name, timeout=a.timeout, order=a.order,
                    path=case["path"], runner_up=case["runner_up"], scene=case["scene"],
                    memories=case["memories"], history=case["history"],
                    events=case["events"],
                    offered=offered, offered_actions=offered_actions)
                rec["raw"] = raw
                rec["latency_s"] = lat
                rec["usage"] = usage
                try:
                    rec["out"] = json.loads(raw)
                    rec["valid"] = True
                except Exception as e:
                    rec["out"] = None
                    rec["valid"] = False
                    rec["parse_error"] = str(e)
                if rec["valid"]:
                    rec["schema_warnings"] = lab.validate_turn(rec["out"], case["stage"],
                                                               offered_actions)
                    beats = rec["out"].get("beats") or []
                    rec["first_feeling"] = beats[0].get("feeling") if beats else None
                    rec["read_ok_hit"] = rec["out"].get("read") in case["read_ok"]
                    ok = set(case["feelings_ok"])
                    rec["first_fit"] = rec["first_feeling"] in ok
                    rec["any_fit"] = bool({b.get("feeling") for b in beats} & ok)
                    says = [b.get("say", "") for b in beats]
                    hit, ratio, nearest = lab.copy_metrics(
                        says, lab.fewshot_says(case["stage"], case["path"]))
                    rec["copy_hit"] = hit
                    rec["copy_ratio"] = ratio
                    rec["copy_nearest"] = nearest
                    rec["memory_rejects"] = lab.check_memory(rec["out"].get("memory", ""),
                                                             [case["msg"]])
            except Exception as e:
                rec["valid"] = False
                rec["error"] = f"{type(e).__name__}: {e}"
            doc["results"].append(rec)
            n_done += 1
            out_path.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")
            stat = "VALID" if rec["valid"] else f"FAIL {rec.get('parse_error', rec.get('error', ''))}"
            fit = ""
            if rec["valid"]:
                fit = (f" read={rec['out'].get('read')}{'*' if rec['read_ok_hit'] else '?'}"
                       f" f0={rec['first_feeling']}{'✓' if rec['first_fit'] else '✗'}")
                if rec.get("copy_hit"):
                    fit += f" copy~{rec['copy_ratio']}"
                if rec.get("memory_rejects"):
                    fit += " mem✗"
            print(f"[{n_done}/{n_total}] {case['id']} r{run_i} {rec.get('latency_s', '-')}s "
                  f"{stat}{fit}", flush=True)
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
