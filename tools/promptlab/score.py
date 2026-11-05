#!/usr/bin/env python3
"""Score a prompt-lab results file (P1.20; per-stage gates in P2.21).

Metrics (role-qa-tester gates, docs/07 §5):
  validity        turn parses AND has no schema warnings   gate >= 99%
  read_accuracy   out.read in case.read_ok                  gate >= 85%
  emotion_fit     first beat (or any beat, C10 selector) feeling in
                  case.feelings_ok                          gate >= 85%

v2 (P2.21) applies the three thresholds **per stage at the recorded dose** —
the phase exit criterion — and also reports each stage×path group. The dose is
the steering scale the server was launched with (docs/06 §4); it is recorded on
every row by run.py/plan.py, so a mixed-dose results file cannot silently pass.

Labels come from the versioned set files (sets/*.jsonl), falling back to the
per-run copies stored in the results row — so a LABEL-REV set revision
re-scores honestly while old runs remain auditable.

C10: --beat {first,any} selects which emotion-fit number the pass/fail gate
uses; both numbers are always reported. Default = first (the role gate).

Usage: python tools/promptlab/score.py results/<file>.json [--beat first|any]
"""
import argparse
import json
import math
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
            r["path"] = case.get("path", r.get("path", ""))
            r["events"] = len(case.get("events") or [])
            r["offer_lines"] = sum(1 for e in (case.get("events") or [])
                                   if e.startswith(lab.OFFER_PREFIX))
        r.setdefault("path", "")
        r.setdefault("events", 0)
        r.setdefault("offer_lines", 0)
        if r.get("valid") and r.get("out"):
            out = r["out"]
            beats = out.get("beats") or []
            ok = set(r["feelings_ok"])
            read_intent = (r.get("dose0_read") or
                           (r.get("read_probe") or {}).get("read") or
                           out.get("read"))
            r["read_ok_hit"] = read_intent in r["read_ok"]
            r["first_fit"] = bool(beats) and beats[0].get("feeling") in ok
            r["any_fit"] = bool({b.get("feeling") for b in beats} & ok)
            r["memory_rejects"] = lab.check_memory(out.get("memory", ""), [r["msg"]])
        rows.append(r)
    return rows


def _group(rows, key):
    """Metric block for a set of rows; validity counts warnings as invalid."""
    n = len(rows)
    valid = [r for r in rows if r.get("valid") and not r.get("schema_warnings")]
    doses = sorted({lab.dose_key(r.get("dose")) for r in rows
                    if r.get("dose") is not None})
    n_valid = len(valid)
    read_hits = sum(r.get("read_ok_hit", False) for r in valid)
    first_hits = sum(r.get("first_fit", False) for r in valid)
    any_hits = sum(r.get("any_fit", False) for r in valid)
    return {
        "n": n,
        "valid": n_valid,
        "validity": (n_valid / n) if n else 0.0,
        "read": (read_hits / n_valid) if n_valid else 0.0,
        "first": (first_hits / n_valid) if n_valid else 0.0,
        "any": (any_hits / n_valid) if n_valid else 0.0,
        "dose": doses[0] if len(doses) == 1 else None,
        "doses": doses,
    }


def _p95(values):
    """Nearest-rank p95 (the QA report's latency tail, role-qa-tester standards)."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(0.95 * len(ordered)))
    return ordered[rank - 1]


def wilson(hits, n, z=1.959963984540054):
    """Wilson 95 % interval for a proportion.

    A per-stage gate over ~10 scripted prompts per stage×path cannot resolve
    85 % to a point (review DES-1): 8/10 has a 95 % interval of roughly 44–97 %.
    """
    if not n:
        return (0.0, 1.0)
    p = hits / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def _fisher_prob(a, b, c, d):
    n = a + b + c + d
    return (math.comb(a + b, a) * math.comb(c + d, c)) / math.comb(n, a + c)


def fisher_exact(a, b, c, d):
    """Two-sided Fisher exact p for the table [[a, b], [c, d]]."""
    row1, col1 = a + b, a + c
    obs = _fisher_prob(a, b, c, d)
    total = 0.0
    for x in range(max(0, col1 - (c + d)), min(row1, col1) + 1):
        p = _fisher_prob(x, row1 - x, col1 - x, (c + d) - (col1 - x))
        if p <= obs + 1e-12:
            total += p
    return min(1.0, total)


def prompt_hits(rows, metric, run=1):
    """(hits, n) over distinct scripted prompts, one draw each.

    The run-level tables count every prompt twice (two draws at temperature
    0.75–0.95), and two draws of one prompt are not independent samples. A
    per-prompt test therefore takes one draw per prompt (review DES-2).
    """
    per_case = {}
    for r in rows:
        if r.get("run") != run or not r.get("valid") or r.get("schema_warnings"):
            continue
        per_case[r.get("id")] = bool(r.get(metric))
    return sum(per_case.values()), len(per_case)


def pair_counts(rows_a, rows_b, metric, run=1):
    """Controlled same-population pair: (a_hits, a_n, b_hits, b_n, fisher_p)."""
    a, na = prompt_hits(rows_a, metric, run)
    b, nb = prompt_hits(rows_b, metric, run)
    p = fisher_exact(a, na - a, b, nb - b) if na and nb else None
    return a, na, b, nb, p


def score(doc, labels=None):
    res = annotate(doc, labels)
    m = _group(res, None)
    # keep the v1 key names on the top-level block (report/score consumers)
    m["read_accuracy"] = m["read"]
    m["first_fit"] = m["first"]
    m["any_fit"] = m["any"]
    m["rows"] = res  # annotated rows for report.py

    per_stage = {}
    per_group = {}
    for st in sorted({r["stage"] for r in res}):
        block = _group([r for r in res if r["stage"] == st], None)
        paths = {}
        for path in sorted({r.get("path", "") for r in res if r["stage"] == st}):
            key = path or "none"
            paths[key] = _group([r for r in res
                                 if r["stage"] == st and r.get("path", "") == path], None)
            per_group[f"{st}:{key}"] = paths[key]
        block["paths"] = paths
        per_stage[st] = block
    m["per_stage"] = per_stage
    m["per_group"] = per_group

    def cp(rows):
        rows = list(rows)
        return (sum(bool(r.get("copy_hit")) for r in rows) / len(rows)) if rows else 0.0
    valid = [r for r in res if r.get("valid") and not r.get("schema_warnings")]
    near = [r for r in valid if r.get("near_fewshot")]
    held = [r for r in valid if not r.get("near_fewshot")]
    m["copy"] = {"overall": cp(valid), "near_fewshot": cp(near), "held_out": cp(held),
                 "n_near": len(near), "n_held": len(held),
                 "avg_ratio": round(sum(r.get("copy_ratio", 0) for r in valid) / len(valid), 3)
                 if valid else 0}
    proposed = [r for r in valid if (r.get("out") or {}).get("memory")]
    m["memory"] = {"proposed": len(proposed),
                   "rejected": sum(1 for r in proposed if r.get("memory_rejects")),
                   "rate": (sum(1 for r in proposed if r.get("memory_rejects")) / len(proposed))
                   if proposed else 0.0}

    lat = [r["latency_s"] for r in res if r.get("latency_s")]
    if lat:
        m["latency"] = {"median": sorted(lat)[len(lat) // 2], "p95": _p95(lat), "n": len(lat)}
    by_dose = {}
    for dose in sorted({lab.dose_key(r.get("dose")) for r in res
                        if r.get("dose") is not None}):
        rows = [r for r in res if lab.dose_key(r.get("dose")) == dose]
        block = _group(rows, None)
        dlat = [r["latency_s"] for r in rows if r.get("latency_s")]
        if dlat:
            block["latency_median"] = sorted(dlat)[len(dlat) // 2]
            block["latency_p95"] = _p95(dlat)
        by_dose[dose] = block
    m["by_dose"] = by_dose
    # A dose on every row is not a sweep: the scheduled run records one dose per
    # stage too. Only a document whose meta says it swept may print a dose gate
    # (review CODE-2 in report.py, CODE-r2-2 in this console block).
    m["sweep_doses"] = sorted(float(d) for d in
                              ((doc.get("meta") or {}).get("sweep_doses") or []))
    return m


def gate_rows(m, beat):
    """(label, value, threshold, ok) for the overall gate and every stage gate."""
    out = [("overall validity", m["validity"], GATES["validity"]),
           ("overall read_accuracy", m["read_accuracy"], GATES["read_accuracy"]),
           (f"overall {beat}_beat_fit",
            m["first_fit"] if beat == "first" else m["any_fit"], GATES["emotion_fit"])]
    rows = []
    for label, value, threshold in out:
        rows.append((label, value, threshold, value >= threshold))
    stage_rows = []
    for st, s in sorted(m["per_stage"].items()):
        if not s["n"]:
            continue
        stage_rows.append((f"stage {st} validity", s["validity"], GATES["validity"],
                           s["validity"] >= GATES["validity"]))
        stage_rows.append((f"stage {st} read_accuracy", s["read"], GATES["read_accuracy"],
                           s["read"] >= GATES["read_accuracy"]))
        fit = s["first"] if beat == "first" else s["any"]
        stage_rows.append((f"stage {st} {beat}_beat_fit", fit, GATES["emotion_fit"],
                           fit >= GATES["emotion_fit"]))
    return rows, stage_rows


def _dose_label(doses):
    if not doses:
        return "?"
    if len(doses) == 1:
        return doses[0]
    return "mixed(%s)" % ",".join(doses)


def print_report(m, beat):
    print(f"n={m['n']}  validity={m['validity']:.1%}  read_accuracy={m['read_accuracy']:.1%}")
    print(f"first_beat_fit={m['first_fit']:.1%}  any_beat_fit={m['any_fit']:.1%}  "
          f"(gate {beat}-beat >= 85%)")
    for st, s in sorted(m["per_stage"].items()):
        if not s["n"]:
            continue
        print(f"  stage {st} (dose {_dose_label(s['doses'])}): n={s['n']} valid={s['valid']}  "
              f"validity={s['validity']:.1%}  read={s['read']:.1%}  "
              f"first={s['first']:.1%}  any={s['any']:.1%}")
        for path, p in sorted(s["paths"].items()):
            print(f"    {path:<8} n={p['n']:<3} valid={p['valid']:<3} validity={p['validity']:.1%}  "
                  f"read={p['read']:.1%}  first={p['first']:.1%}  any={p['any']:.1%}")
    if m["by_dose"]:
        if m.get("sweep_doses"):
            label = "dose sweep (validity is the gate; read/fit informational)"
        else:
            label = ("per-dose (scheduled stage doses, not a sweep — the dose gate is "
                     "measured on the sweep file)")
        print(f"  {label}:")
        for dose, s in sorted(m["by_dose"].items()):
            lat = f"  median={s['latency_median']}s" if s.get("latency_median") else ""
            print(f"    dose {dose:>28}: n={s['n']} valid={s['valid']} validity={s['validity']:.1%}"
                  f"  read={s['read']:.1%}  first={s['first']:.1%}{lat}")
    c = m["copy"]
    print(f"few-shot copy: overall={c['overall']:.1%}  near-fewshot={c['near_fewshot']:.1%} "
          f"(n={c['n_near']})  held-out={c['held_out']:.1%} (n={c['n_held']})  "
          f"avg_ratio={c['avg_ratio']}")
    mm = m["memory"]
    print(f"memory proposals={mm['proposed']}  rejected={mm['rejected']}  rate={mm['rate']:.1%}")
    if m.get("latency"):
        print(f"latency: median={m['latency']['median']}s p95={m['latency']['p95']}s "
              f"(n={m['latency']['n']})")

    misses = [r for r in m["rows"] if r.get("valid") and not r.get("schema_warnings")
              and not r.get("first_fit")]
    if misses:
        print("\nfirst-beat misses (top 5):")
        for r in misses[:5]:
            b0 = r["out"]["beats"][0]
            print(f"  {r['id']} r{r['run']} s{r['stage']} {r.get('path') or '-':<7} "
                  f"{r['msg'][:46]!r}\n"
                  f"    picked {r['out']['beats'][0].get('feeling')!r}  "
                  f"ok={sorted(r['feelings_ok'])}\n"
                  f"    inner={r['out'].get('inner', '')!r}\n    say={b0['say'][:110]!r}")

    overall, per_stage = gate_rows(m, beat)
    print()
    for label, value, threshold, ok in overall + per_stage:
        print(f"{'PASS' if ok else 'FAIL'} {label}: {value:.1%} (gate {threshold:.0%})")
    return all(row[3] for row in overall + per_stage)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("results")
    p.add_argument("--beat", choices=["first", "any"], default="first",
                   help="which emotion-fit metric the 85%% gate applies to (default first)")
    a = p.parse_args()
    doc = json.loads(Path(a.results).read_text(encoding="utf-8"))
    m = score(doc)
    ok = print_report(m, a.beat)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
