#!/usr/bin/env python3
"""Score a prompt-lab results file (P1.20).

Metrics (role-qa-tester gates):
  validity        turn parses AND has no schema warnings   gate >= 99%
  read_accuracy   out.read in case.read_ok                  gate >= 85%
  emotion_fit     first beat (or any beat, C10 selector) feeling in
                  case.feelings_ok                          gate >= 85%

Labels come from the versioned set files (sets/*_main.jsonl), falling back to
the per-run copies stored in the results row — so a LABEL-REV set revision
re-scores honestly while old runs remain auditable.

C10: --beat {first,any} selects which emotion-fit number the pass/fail gate
uses; both numbers are always reported. Default = first (the role gate; D10
carried the first-beat gap here for label-set quality review, not relabeling).

Usage: python tools/promptlab/score.py results/<file>.json [--beat first|any]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab

GATES = {"validity": 0.99, "read_accuracy": 0.85, "emotion_fit": 0.85}


def load_labels(sets_dir=None):
    """id -> case from every JSONL in sets/ (the versioned label authority)."""
    d = Path(sets_dir) if sets_dir else lab.SETS_DIR
    labels = {}
    for f in sorted(d.glob("*.jsonl")):
        for c in lab.load_set(f):
            labels[c["id"]] = c
    return labels


def annotate(doc, labels=None):
    """Re-derive per-row metrics from the versioned labels (or row-embedded ones)."""
    labels = labels if labels is not None else load_labels()
    rows = []
    for r in doc["results"]:
        r = dict(r)
        case = labels.get(r["id"])
        if case:
            r["read_ok"] = case["read_ok"]
            r["feelings_ok"] = case["feelings_ok"]
            r["near_fewshot"] = case.get("near_fewshot", False)
        if r.get("valid") and r.get("out"):
            out = r["out"]
            beats = out.get("beats") or []
            ok = set(r["feelings_ok"])
            r["read_ok_hit"] = out.get("read") in r["read_ok"]
            r["first_fit"] = bool(beats) and beats[0].get("feeling") in ok
            r["any_fit"] = bool({b.get("feeling") for b in beats} & ok)
            r["memory_rejects"] = lab.check_memory(out.get("memory", ""), [r["msg"]])
        rows.append(r)
    return rows


def score(doc, labels=None):
    res = annotate(doc, labels)
    n = len(res) or 1
    valid = [r for r in res if r.get("valid") and not r.get("schema_warnings")]
    m = {"n": len(res),
         "validity": len(valid) / n,
         "read_accuracy": sum(r.get("read_ok_hit", False) for r in valid) / len(valid) if valid else 0.0,
         "first_fit": sum(r.get("first_fit", False) for r in valid) / len(valid) if valid else 0.0,
         "any_fit": sum(r.get("any_fit", False) for r in valid) / len(valid) if valid else 0.0}
    m["per_stage"] = {}
    for st in sorted({r["stage"] for r in res}):
        v = [r for r in valid if r["stage"] == st]
        allst = [r for r in res if r["stage"] == st]
        if not v:
            m["per_stage"][st] = {"n": len(allst), "valid": 0}
            continue
        m["per_stage"][st] = {"n": len(allst), "valid": len(v),
                              "read": sum(r["read_ok_hit"] for r in v) / len(v),
                              "first": sum(r["first_fit"] for r in v) / len(v),
                              "any": sum(r["any_fit"] for r in v) / len(v)}

    def cp(rows):
        rows = list(rows)
        return (sum(r.get("copy_hit") for r in rows) / len(rows)) if rows else 0.0
    near = [r for r in valid if r.get("near_fewshot")]
    held = [r for r in valid if not r.get("near_fewshot")]
    m["copy"] = {"overall": cp(valid), "near_fewshot": cp(near), "held_out": cp(held),
                 "n_near": len(near), "n_held": len(held),
                 "avg_ratio": round(sum(r.get("copy_ratio", 0) for r in valid) / len(valid), 3) if valid else 0}
    proposed = [r for r in valid if (r.get("out") or {}).get("memory")]
    m["memory"] = {"proposed": len(proposed),
                   "rejected": sum(1 for r in proposed if r.get("memory_rejects")),
                   "rate": (sum(1 for r in proposed if r.get("memory_rejects")) / len(proposed))
                   if proposed else 0.0}
    lat = [r["latency_s"] for r in res if r.get("latency_s")]
    if lat:
        lat.sort()
        m["latency"] = {"median": lat[len(lat) // 2], "p95": lat[min(len(lat) - 1, int(len(lat) * 0.95))],
                        "n": len(lat)}
    m["rows"] = res  # annotated rows for report.py
    return m


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("results")
    p.add_argument("--beat", choices=["first", "any"], default="first",
                   help="which emotion-fit metric the 85%% gate applies to (default first)")
    a = p.parse_args()
    doc = json.loads(Path(a.results).read_text(encoding="utf-8"))
    m = score(doc)
    fit_gate = m["first_fit"] if a.beat == "first" else m["any_fit"]

    print(f"n={m['n']}  validity={m['validity']:.1%}  read_accuracy={m['read_accuracy']:.1%}")
    print(f"first_beat_fit={m['first_fit']:.1%}  any_beat_fit={m['any_fit']:.1%}  "
          f"(gate {a.beat}-beat >= 85%)")
    for st, s in sorted(m["per_stage"].items()):
        if s.get("valid"):
            print(f"  stage {st}: n={s['n']} valid={s['valid']}  read={s['read']:.1%}  "
                  f"first={s['first']:.1%}  any={s['any']:.1%}")
        else:
            print(f"  stage {st}: n={s['n']} valid={s['valid']}")
    c = m["copy"]
    print(f"few-shot copy: overall={c['overall']:.1%}  near-fewshot={c['near_fewshot']:.1%} (n={c['n_near']})  "
          f"held-out={c['held_out']:.1%} (n={c['n_held']})  avg_ratio={c['avg_ratio']}")
    mm = m["memory"]
    print(f"memory proposals={mm['proposed']}  rejected={mm['rejected']}  rate={mm['rate']:.1%}")
    if m.get("latency"):
        print(f"latency: median={m['latency']['median']}s p95={m['latency']['p95']}s (n={m['latency']['n']})")

    misses = [r for r in m["rows"] if r.get("valid") and not r.get("schema_warnings")
              and not r.get("first_fit")]
    if misses:
        print("\nfirst-beat misses (top 5):")
        for r in misses[:5]:
            b0 = r["out"]["beats"][0]
            print(f"  {r['id']} r{r['run']} s{r['stage']} {r['msg'][:50]!r}\n"
                  f"    picked {r['out']['beats'][0].get('feeling')!r}  ok={sorted(r['feelings_ok'])}\n"
                  f"    inner={r['out'].get('inner', '')!r}\n    say={b0['say'][:110]!r}")

    checks = [("validity", m["validity"], GATES["validity"]),
              ("read_accuracy", m["read_accuracy"], GATES["read_accuracy"]),
              (f"{a.beat}_beat_fit", fit_gate, GATES["emotion_fit"])]
    ok = all(v >= t for _, v, t in checks)
    print("\n" + "\n".join(f"{'PASS' if v >= t else 'FAIL'} {k}: {v:.1%} (gate {t:.0%})"
                           for k, v, t in checks))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
