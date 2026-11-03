#!/usr/bin/env python3
"""Emit the prompt-lab report (Markdown + HTML) for a results file (P1.20).

    python tools/promptlab/report.py results/<file>.json [--beat first|any] [--out reports/<name>]

Writes <out>.md and <out>.html (default: tools/promptlab/reports/<date>_<results-stem>).
"""
import argparse
import html as html_lib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab
from score import GATES, score

BASELINES = {
    "experiments/results_v3.json (Linux stage 0+4, v1 labels)": "100% valid · 90.0% read · 80.0% first / 86.7% any",
    "experiments/windows/tool_test_v3.json (Windows, n=45, v1 labels)": "100% valid · 97.8% read · 84.4% first / 93.3% any",
}


def md_report(doc, beat):
    m = score(doc)
    meta = doc.get("meta", {})
    fit = m["first_fit"] if beat == "first" else m["any_fit"]
    lines = []
    A = lines.append
    A(f"# Prompt lab report — {meta.get('date', '?')}")
    A("")
    A(f"- results: `{meta.get('sets', '?')}` × {meta.get('runs_per_case', '?')} runs "
      f"(n={m['n']})")
    A(f"- server: `{meta.get('url')}` · model `{Path(str(meta.get('model'))).name}`")
    A(f"- sampling: docs/02 §9 per stage ({meta.get('sampling')}); thinking off")
    A(f"- dose: {meta.get('dose_note', 'n/a')}")
    A(f"- prompts: real `game/data/prompts/` files, docs/08 §1 assembly, player name "
      f"`{meta.get('player_name')}`")
    A("")
    A("## Metrics vs gates")
    A("")
    A("| metric | value | gate | verdict |")
    A("|---|---|---|---|")
    v = m["validity"]
    A(f"| JSON validity | {v:.1%} | ≥ {GATES['validity']:.0%} | {'PASS' if v >= GATES['validity'] else 'FAIL'} |")
    v = m["read_accuracy"]
    A(f"| intent (read) accuracy | {v:.1%} | ≥ {GATES['read_accuracy']:.0%} | {'PASS' if v >= GATES['read_accuracy'] else 'FAIL'} |")
    A(f"| emotion fit — **{beat}-beat (gate)** | {fit:.1%} | ≥ {GATES['emotion_fit']:.0%} | "
      f"{'PASS' if fit >= GATES['emotion_fit'] else 'FAIL'} |")
    other = "any" if beat == "first" else "first"
    ov = m["any_fit"] if beat == "first" else m["first_fit"]
    A(f"| emotion fit — {other}-beat (informational, C10) | {ov:.1%} | — | — |")
    A("")
    A("| stage | n | valid | read | first-beat fit | any-beat fit |")
    A("|---|---|---|---|---|---|")
    for st, s in sorted(m["per_stage"].items()):
        if s.get("valid"):
            A(f"| {st} | {s['n']} | {s['valid']} | {s['read']:.1%} | {s['first']:.1%} | {s['any']:.1%} |")
        else:
            A(f"| {st} | {s['n']} | {s['valid']} | — | — | — |")
    A("")
    c = m["copy"]
    A("## Few-shot copy rate (P1.05 DES-2 / CON-4)")
    A("")
    A(f"copy = max `say` similarity ≥ 0.80 to a few-shot `say` of the same stage. "
      f"Overall **{c['overall']:.1%}**; near-few-shot inputs **{c['near_fewshot']:.1%}** "
      f"(n={c['n_near']}); held-out inputs **{c['held_out']:.1%}** (n={c['n_held']}); "
      f"mean max-ratio {c['avg_ratio']}.")
    hits = [r for r in doc["results"] if r.get("copy_hit")]
    if hits:
        A("")
        A("| case | run | sim | generated say | nearest few-shot say |")
        A("|---|---|---|---|---|")
        for r in hits[:10]:
            A(f"| {r['id']} | {r['run']} | {r['copy_ratio']} | {r['out']['beats'] and ' / '.join(b['say'] for b in r['out']['beats'])} | {r.get('copy_nearest')} |")
    A("")
    mm = m["memory"]
    A("## Memory rejection rate (P1.05 CON-2)")
    A("")
    A(f"Non-empty `memory` proposals: {mm['proposed']}; rejected by docs/02 §6 rules 1–2 "
      f"(meta/schema words or no shared content word): {mm['rejected']} "
      f"(**{mm['rate']:.1%}**).")
    rej = [r for r in doc["results"] if r.get("memory_rejects")]
    if rej:
        A("")
        A("| case | run | memory | rejected because |")
        A("|---|---|---|---|")
        for r in rej[:10]:
            A(f"| {r['id']} | {r['run']} | `{r['out'].get('memory','')}` | {'; '.join(r['memory_rejects'])} |")
    A("")
    if m.get("latency"):
        A(f"## Latency: median {m['latency']['median']} s, p95 {m['latency']['p95']} s "
          f"(n={m['latency']['n']}, this host/server)")
        A("")
    A("## Baselines for comparison")
    A("")
    for k, v in BASELINES.items():
        A(f"- `{k}` — {v}")
    A("")
    misses = [r for r in doc["results"] if r.get("valid") and not r.get("schema_warnings")
              and not r.get("first_fit")]
    if misses:
        A("## First-beat misses (all, for the D10 label-set review)")
        A("")
        for r in misses:
            b0 = r["out"]["beats"][0]
            A(f"- `{r['id']}` run {r['run']} — msg {r['msg']!r}")
            A(f"  - picked `{r['first_feeling']}`, acceptable: {sorted(r['feelings_ok'])}")
            A(f"  - inner: {r['out'].get('inner', '')!r}")
            A(f"  - say: {b0['say']!r}")
        A("")
    bad = [r for r in doc["results"] if not r.get("valid") or r.get("schema_warnings")]
    if bad:
        A("## Invalid / schema-warning turns")
        A("")
        for r in bad:
            A(f"- `{r['id']}` run {r['run']}: {r.get('parse_error') or r.get('error') or r.get('schema_warnings')}")
            if r.get("raw"):
                A(f"  - raw: `{r['raw'][:200]}`")
        A("")
    return "\n".join(lines)


def md_to_html(md, title):
    """Tiny markdown → standalone HTML (headers, tables, lists, code, bold)."""
    out = [f"<!doctype html><meta charset=utf-8><title>{html_lib.escape(title)}</title>",
           "<style>body{font:15px/1.5 system-ui,sans-serif;max-width:1100px;margin:2em auto;padding:0 1em;color:#222}",
           "table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px 10px;text-align:left}",
           "th{background:#eee}code{background:#f4f4f4;padding:1px 4px;border-radius:3px}",
           "h1,h2{border-bottom:1px solid #ddd;padding-bottom:.2em}h2{margin-top:1.6em}",
           "li{margin:.2em 0}.fail{color:#b00;font-weight:700}.pass{color:#070;font-weight:700}</style>"]
    in_table = in_list = False
    for line in md.splitlines():
        esc = html_lib.escape(line)
        esc = esc.replace("**", "§B§")
        import re as _re
        esc = _re.sub(r"§B§(.*?)§B§", r"<b>\1</b>", esc)
        esc = _re.sub(r"`(.*?)`", r"<code>\1</code>", esc)
        esc = esc.replace("PASS", '<span class=pass>PASS</span>').replace("FAIL", '<span class=fail>FAIL</span>')
        if line.startswith("|") and line.endswith("|"):
            cells = [c.strip() for c in line.strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue
            if not in_table:
                out.append("<table>")
                in_table = True
                tag = "th"
            else:
                tag = "td"
            out.append("<tr>" + "".join(f"<{tag}>{html_lib.escape(c).replace('§B§','')}</{tag}>"
                                        for c in cells) + "</tr>")
            continue
        if in_table:
            out.append("</table>")
            in_table = False
        if line.startswith("## "):
            out.append(f"<h2>{esc[3:]}</h2>")
        elif line.startswith("# "):
            out.append(f"<h1>{esc[2:]}</h1>")
        elif line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{esc[2:]}</li>")
        elif line.startswith("  - "):
            out.append(f"<li style='margin-left:2em;list-style:circle'>{esc[6:]}</li>")
        else:
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append(f"<p>{esc}</p>" if esc else "")
    if in_table:
        out.append("</table>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("results")
    p.add_argument("--beat", choices=["first", "any"], default="first")
    p.add_argument("--out", default=None)
    a = p.parse_args()
    doc = json.loads(Path(a.results).read_text(encoding="utf-8"))
    stem = a.out or str(lab.REPORTS_DIR / f"{time.strftime('%Y-%m-%d')}_{Path(a.results).stem}")
    Path(stem).parent.mkdir(parents=True, exist_ok=True)
    md = md_report(doc, a.beat)
    Path(stem + ".md").write_text(md, encoding="utf-8")
    Path(stem + ".html").write_text(md_to_html(md, "prompt lab report"), encoding="utf-8")
    print(f"wrote {stem}.md and {stem}.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
