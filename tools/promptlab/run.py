#!/usr/bin/env python3
"""Prompt lab runner (P1.20): run a label set against a live llama-server.

One command, from the repo/worktree root:
    python tools/promptlab/run.py
Writes results JSON incrementally to tools/promptlab/results/ (re-runnable:
cases already present in the results file are skipped, so Ctrl-C is cheap).
Then score + report:
    python tools/promptlab/score.py  tools/promptlab/results/<file>.json
    python tools/promptlab/report.py tools/promptlab/results/<file>.json
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default=lab.DEFAULT_URL)
    p.add_argument("--sets", nargs="*", default=None,
                   help="set files under tools/promptlab/sets/ (default: all *_main.jsonl)")
    p.add_argument("--runs", type=int, default=2, help="runs per case (default 2)")
    p.add_argument("--out", default=None, help="results JSON path (default results/<ts>_<set>.json)")
    p.add_argument("--only", nargs="*", default=None, help="run only these case ids")
    p.add_argument("--max-cases", type=int, default=None)
    p.add_argument("--timeout", type=int, default=900)
    a = p.parse_args()

    set_paths = a.sets or sorted(lab.SETS_DIR.glob("*_main.jsonl"))
    cases = []
    for sp in set_paths:
        cases += lab.load_set(sp)

    out_path = Path(a.out) if a.out else lab.RESULTS_DIR / f"{time.strftime('%Y-%m-%d')}_v1.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if out_path.exists():
        doc = json.loads(out_path.read_text(encoding="utf-8"))
        done = {(r["id"], r["run"]) for r in doc["results"]}
        print(f"resuming: {len(done)} turns already in {out_path.name}")
    else:
        props = lab.server_props(a.url)
        doc = {"meta": {"task": "P1.20 prompt lab v1",
                        "date": time.strftime("%Y-%m-%d %H:%M"),
                        "url": a.url,
                        "model": props.get("model_path") or props.get("model_alias") or "?",
                        "control_vector": props.get("default_generation_settings", {})
                                             .get("params", {}).get("control_vector", None),
                        "sampling": lab.SAMPLING,
                        "dose_note": "llama-server has no control vector loaded — all stages run "
                                     "at dose 0 (dose is a launch flag, not per-request).",
                        "player_name": lab.PLAYER_NAME,
                        "sets": [str(s) for s in set_paths],
                        "runs_per_case": a.runs},
               "results": []}
        done = set()

    n_total = sum(a.runs for c in cases if not a.only or c["id"] in a.only)
    if a.max_cases:
        n_total = min(n_total, a.max_cases * a.runs)
    n_done = 0
    for case in cases:
        if a.only and case["id"] not in a.only:
            continue
        for run_i in range(1, a.runs + 1):
            if (case["id"], run_i) in done:
                n_done += 1
                continue
            if a.max_cases and n_done >= a.max_cases * a.runs:
                break
            rec = {"id": case["id"], "stage": case["stage"], "run": run_i,
                   "msg": case["msg"], "near_fewshot": case["near_fewshot"],
                   "read_ok": case["read_ok"], "feelings_ok": case["feelings_ok"]}
            try:
                raw, lat, usage = lab.post_turn(a.url, case["stage"], case["msg"], timeout=a.timeout)
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
                    rec["schema_warnings"] = lab.validate_turn(rec["out"], case["stage"])
                    beats = rec["out"].get("beats") or []
                    rec["first_feeling"] = beats[0].get("feeling") if beats else None
                    rec["read_ok_hit"] = rec["out"].get("read") in case["read_ok"]
                    ok = set(case["feelings_ok"])
                    rec["first_fit"] = rec["first_feeling"] in ok
                    rec["any_fit"] = bool({b.get("feeling") for b in beats} & ok)
                    says = [b.get("say", "") for b in beats]
                    hit, ratio, nearest = lab.copy_metrics(says, lab.fewshot_says(case["stage"]))
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
                fit = f" read={rec['out'].get('read')}{'*' if rec['read_ok_hit'] else '?'}" \
                      f" f0={rec['first_feeling']}{'✓' if rec['first_fit'] else '✗'}"
                if rec.get("copy_hit"):
                    fit += f" copy~{rec['copy_ratio']}"
                if rec.get("memory_rejects"):
                    fit += " mem✗"
            print(f"[{n_done}/{n_total}] {case['id']} r{run_i} {rec.get('latency_s','-')}s {stat}{fit}",
                  flush=True)
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
