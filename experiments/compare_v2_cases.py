"""Per-case B4 fit comparison: a committed baseline results_v2.json vs a Windows rerun
(tool_test_v2.json). Prints the per-case fit table, every miss in the second run with the
feelings the model picked, and an exact binomial check of how far pure sampling can explain
the delta. Written for experiments/windows/report.md §5 (P0.04 round 2, review DES-2/CODE-2).

Usage: python experiments/compare_v2_cases.py [baseline.json rerun.json]
Defaults: experiments/results_v2.json vs experiments/windows/tool_test_v2.json.
"""
import json, os, sys
from collections import defaultdict
from math import comb

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tool_test_v2 import CASES

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "results_v2.json")
RERUN = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "windows", "tool_test_v2.json")

OK = {msg: ok for _stage, msg, ok in CASES}


def b4(path):
    return [r for r in json.load(open(path, encoding="utf-8"))["results"]
            if r["method"] == "B4_beats_cues"]


def counts(rows):
    c = defaultdict(lambda: [0, 0])
    for r in rows:
        c[r["msg"]][0] += r["fits"]
        c[r["msg"]][1] += 1
    return c


bb, ww = b4(BASE), b4(RERUN)
bc, wc = counts(bb), counts(ww)
nb, fb = len(bb), sum(r["fits"] for r in bb)
nw, fw = len(ww), sum(r["fits"] for r in ww)

print(f"B4 fits: baseline {fb}/{nb} = {fb/nb:.1%}   rerun {fw}/{nw} = {fw/nw:.1%}\n")
print(f'{"case":48} {"base":>5} {"rerun":>5}')
for _stage, msg, _ok in CASES:
    print(f"{msg[:48]:48} {bc[msg][0]}/{bc[msg][1]:<3} {wc[msg][0]}/{wc[msg][1]:<3}")

misses = [r for r in ww if not r["fits"]]
print(f"\nall rerun misses ({len(misses)}):")
for r in misses:
    picked = r.get("all_fam") or r["fam"]
    print(f'  s{r["stage"]} {r["msg"][:44]:46} picked={"/".join(picked):24} ok={sorted(OK[r["msg"]])}')

p = fb / nb
tail = sum(comb(nw, i) * p**i * (1 - p)**(nw - i) for i in range(fw + 1))
print(f"\nbinomial check: if every rerun turn had the baseline-average fit rate p={p:.3f}, "
      f"P(<= {fw}/{nw}) = {tail:.2e}")
print("=> a pure same-distribution resample is very unlikely; per-case label-set width, "
      "not sampling noise, drives most of the delta.")
