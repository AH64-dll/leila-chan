#!/usr/bin/env python3
"""Emit the prompt-lab report (Markdown + HTML) for a results file (v3 in P3.19).

    python tools/promptlab/report.py results/<file>.json [--beat first|any] [--out reports/<name>]

Writes <out>.md and <out>.html (default: tools/promptlab/reports/<results-stem>).
Safety sections are filled from `<results-stem>.safety.json` (the real filter
scan) and `<results-stem>.judge.json` (the independent classifier judge) when
those files exist next to the results, or from --safety/--judge. The P3.19 path
separation metric comes from `<results-stem>.path_judge.json` (path_judge.py).
"""
import argparse
import html as html_lib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab
from score import (GATES, _dose_label, pair_counts, prompt_hits, score, wilson)

BASELINES = {
    "tools/promptlab/reports/2026-11-03_v1.md (stages 0+1, dose 0, n=60)":
        "100% valid · 93.3% read · 100% first-beat fit",
    "experiments/results_v3.json (Linux stage 0+4, v1 labels)":
        "100% valid · 90.0% read · 80.0% first / 86.7% any",
    "experiments/windows/tool_test_v3.json (Windows, n=45, v1 labels)":
        "100% valid · 97.8% read · 84.4% first / 93.3% any",
}


def _pct(value):
    return f"{value:.1%}"


def _p(value):
    """Fisher exact p; a dash when the pair has no rows on one side."""
    if value is None:
        return "—"
    return "< 0.001" if value < 0.001 else f"{value:.3f}"


def _verdict(ok):
    return "PASS" if ok else "FAIL"


def _load_side(stem, kind, explicit):
    path = Path(explicit) if explicit else Path(str(stem) + f".{kind}.json")
    if path.is_file():
        return json.loads(path.read_text(encoding="utf-8")), path
    return None, path


def md_report(doc, beat, safety=None, judge=None, safety_path=None, judge_path=None,
              path_judge=None, path_judge_path=None):
    m = score(doc)                      # scored on the versioned set labels
    m0 = score(doc, labels={})          # scored on labels frozen at run time
    rows = m["rows"]
    meta = doc.get("meta", {})
    fit = m["first_fit"] if beat == "first" else m["any_fit"]
    lines = []
    A = lines.append
    A(f"# Prompt lab v3 report — {meta.get('date', '?')}")
    A("")
    A(f"- results: `{meta.get('sets', [])}` × "
      f"{meta.get('runs_per_case', '?')} runs (n={m['n']})")
    A(f"- server: `{meta.get('url')}` · model `{meta.get('model')}` "
      f"({meta.get('model_ftype')}) · build `{meta.get('build_info')}`")
    if meta.get("host"):
        A(f"- host: {meta['host']}")
    A(f"- sampling: docs/02 §9 per stage {meta.get('sampling')}; thinking off")
    doses = meta.get("doses") or {}
    if doses:
        A(f"- **scheduled doses (docs/02 §9)**: "
          + " · ".join(f"stage {k} → {v:g}" for k, v in sorted(doses.items())))
    if meta.get("sweep_doses"):
        A(f"- **dose sweep**: {', '.join('%g' % d for d in meta['sweep_doses'])} "
          "(same probe set, one server launch per dose)")
    A(f"- prompts: real `game/data/prompts/` files, docs/08 §1 eight-layer assembly "
      f"(persona, player, stage, path+runner-up, scene, memories, events, rules), "
      f"player name `{meta.get('player_name')}`")
    A("")
    scheduled = bool(meta.get("doses"))
    if scheduled:
        A("## Acceptance: per-stage gates at the scheduled dose")
        A("")
        A("| stage | dose | n | JSON validity | intent (read) | emotion fit "
          f"({beat}-beat) | verdict |")
        A("|---|---|---|---|---|---|---|")
        for st, s in sorted(m["per_stage"].items()):
            if not s["n"]:
                continue
            fit_s = s["first"] if beat == "first" else s["any"]
            ok = (s["validity"] >= GATES["validity"] and s["read"] >= GATES["read_accuracy"]
                  and fit_s >= GATES["emotion_fit"])
            A(f"| {st} | {_dose_label(s['doses'])} | {s['n']} | {_pct(s['validity'])} "
              f"(≥99%) | {_pct(s['read'])} (≥85%) | {_pct(fit_s)} (≥85%) | {_verdict(ok)} |")
    else:
        A("## Per-stage metrics (informational — this run is not the scheduled-dose gate)")
        A("")
        A("The gate applies to the scheduled-dose run; this file mixes doses by design "
          "(see the dose table below), so per-stage numbers here track the dose, not a stage.")
        A("")
        A("| stage | doses | n | JSON validity | intent (read) | emotion fit "
          f"({beat}-beat) |")
        A("|---|---|---|---|---|---|")
        for st, s in sorted(m["per_stage"].items()):
            if not s["n"]:
                continue
            fit_s = s["first"] if beat == "first" else s["any"]
            A(f"| {st} | {_dose_label(s['doses'])} | {s['n']} | {_pct(s['validity'])} | "
              f"{_pct(s['read'])} | {_pct(fit_s)} |")
    A("")
    A("### Gate resolution (95 % Wilson interval)")
    A("")
    A("A per-stage gate over ~10 scripted prompts per stage×path cannot resolve 85 % to a "
      "point — 8/10 has a 95 % interval of roughly 49–94 % — so the interval is printed with "
      "the point estimate. The unit is the **prompt**, one draw each: two draws of one prompt "
      "are not independent samples (review DES-1, DES-2; DCR on the docs/07 §5 set size).")
    A("")
    A(f"| stage | prompts | read hits | read 95% CI | {beat}-beat hits | "
      f"{beat}-beat 95% CI |")
    A("|---|---|---|---|---|---|")
    for st, s in sorted(m["per_stage"].items()):
        if not s["valid"]:
            continue
        stage_rows = [r for r in m["rows"] if r["stage"] == st]
        rh, n_prompts = prompt_hits(stage_rows, "read_ok_hit")
        fh, _ = prompt_hits(stage_rows, "first_fit" if beat == "first" else "any_fit")
        rl, rx = wilson(rh, n_prompts)
        fl, fx = wilson(fh, n_prompts)
        A(f"| {st} | {n_prompts} | {rh}/{n_prompts} | {_pct(rl)}–{_pct(rx)} | "
          f"{fh}/{n_prompts} | {_pct(fl)}–{_pct(fx)} |")
    A("")
    m_frozen = score(doc, labels={})
    A("### Label-set revision effect (D10)")
    A("")
    A("Frozen labels are the copies stored in the results rows at run time; versioned "
      "labels are the current `sets/` files. A revision is only allowed with quoted "
      "transcript evidence in the case's `notes` (`LABEL-REV3`).")
    A("")
    A("| group | read (frozen) | read (versioned) | first-beat (frozen) | "
      "first-beat (versioned) |")
    A("|---|---|---|---|---|")
    A(f"| overall | {_pct(m_frozen['read_accuracy'])} | {_pct(m['read_accuracy'])} | "
      f"{_pct(m_frozen['first_fit'])} | {_pct(m['first_fit'])} |")
    for st, s in sorted(m["per_stage"].items()):
        f = m_frozen["per_stage"].get(st)
        if not f or not f["n"]:
            continue
        A(f"| stage {st} | {_pct(f['read'])} | {_pct(s['read'])} | "
          f"{_pct(f['first'])} | {_pct(s['first'])} |")
    A("")
    A("## Per stage × path (informational)")
    A("")
    A("| stage | path | n | valid | validity | read | first-beat | any-beat |")
    A("|---|---|---|---|---|---|---|---|")
    for st, s in sorted(m["per_stage"].items()):
        for path, p in sorted(s.get("paths", {}).items()):
            A(f"| {st} | {path} | {p['n']} | {p['valid']} | {_pct(p['validity'])} | "
              f"{_pct(p['read'])} | {_pct(p['first'])} | {_pct(p['any'])} |")
    A("")
    # --- path separation (P3.19: blind judge names the path, docs/07 §5) -----
    if path_judge is not None:
        A("## Path separation — blind judge names the path (P3.19, docs/07 §5)")
        A("")
        pj_meta = path_judge.get("meta") or {}
        A(f"- judged file: `{pj_meta.get('results', '?')}` · "
          f"{path_judge.get('overall', {}).get('n', 0)} transcripts, "
          f"runs {pj_meta.get('runs') or 'all'}")
        A(f"- judge: {pj_meta.get('judge', '?')}")
        A("")
        A("| path | n | correct | accuracy | gate ≥70% |")
        A("|---|---|---|---|---|")
        per_path = path_judge.get("per_path") or {}
        path_names = path_judge.get("paths") or sorted(per_path)
        for name in path_names:
            cell = per_path.get(name) or {}
            A(f"| {name} | {cell.get('n', 0)} | {cell.get('correct', 0)} | "
              f"{_pct(cell.get('accuracy', 0.0))} | "
              f"{_verdict(bool(cell.get('pass')))} |")
        ov = path_judge.get("overall") or {}
        A(f"| **overall** | {ov.get('n', 0)} | {ov.get('correct', 0)} | "
          f"**{_pct(ov.get('accuracy', 0.0))}** | "
          f"**{_verdict(bool(path_judge.get('all_pass')))}** |")
        confusion = path_judge.get("confusion") or {}
        if confusion:
            A("")
            A("Confusion (true → predicted):")
            A("")
            A("| true \\ predicted | " + " | ".join(str(p) for p in path_names)
              + " | other |")
            A("|---|" + "---|" * (len(path_names) + 1))
            for name in path_names:
                row_c = confusion.get(name) or {}
                cells = [str(row_c.get(p) or "") for p in path_names]
                other = sum(v for k, v in row_c.items() if k not in path_names)
                A(f"| {name} | " + " | ".join(cells) + f" | {other or ''} |")
        if path_judge.get("unparsed"):
            A("")
            A(f"Unparsed judge answers: {path_judge['unparsed']} "
              "(counted as misses).")
        A("")
        judge_desc = str(pj_meta.get("judge", ""))
        if "Qwen3.5-4B" in judge_desc:
            A("The judge is the same bare Qwen3.5-4B (no steering vector, temperature 0) — "
              "P3.03 measured its blind-read ceiling at 44% on authored trait text, so a "
              "path below 70% is evidence of weak separation *or* a weak judge; the "
              "per-path numbers and confusion are the review surface either way.")
        else:
            A("The judge is an independent model (not the steered 4B), so a path below "
              "70% here is evidence the generated voice itself is indistinct — a "
              "competent reader could not name the path from the transcript alone. "
              "The per-path numbers and confusion are the review surface.")
        A("")
    by_dose = m.get("by_dose") or {}
    sweep_doses = sorted(float(d) for d in (meta.get("sweep_doses") or []))
    # by_dose is keyed by dose label (dose_key) — a scalar and a dose map share
    # the space, so sweep numbers join through lab.dose_key, not raw floats.
    measured = [(d, lab.dose_key(d)) for d in sweep_doses
                if lab.dose_key(d) in by_dose]
    if measured:
        # Only a run that actually swept doses gets this section: a scheduled run
        # records a dose on every row too, and the section used to claim a sweep
        # (and a criterion-2 PASS) it never measured (review CODE-2).
        A(f"## Dose sweep — JSON schema validity up to dose {max(d for d, _ in measured):g}")
        A("")
        A(f"The same probe set at every dose ({by_dose[measured[0][1]]['n']} turns per dose, one "
          f"server launch per dose — `--control-vector-scaled`, docs/06 §4); doses "
          f"{', '.join('%g' % d for d, _ in measured)}.")
        A("")
        A("| dose | n | valid | validity | read | first-beat | median latency |")
        A("|---|---|---|---|---|---|---|")
        for dose, key in measured:
            s = by_dose[key]
            lat = f"{s['latency_median']} s" if s.get("latency_median") is not None else "—"
            A(f"| {dose:g} | {s['n']} | {s['valid']} | {_pct(s['validity'])} | "
              f"{_pct(s['read'])} | {_pct(s['first'])} | {lat} |")
        worst = min(by_dose[key]["validity"] for _, key in measured)
        ok = all(by_dose[key]["validity"] >= GATES["validity"] for _, key in measured)
        A("")
        A(f"Validity across the sweep: worst {_pct(worst)} — **{_verdict(ok)}** "
          f"(gate ≥ {GATES['validity']:.0%} at every dose).")
        A("")
        A("### Controlled pairs — same probe set, adjacent doses")
        A("")
        A("Per-prompt hit counts (one draw per prompt: the run-level n counts every prompt "
          "twice, and two draws of one prompt are not independent) with a two-sided Fisher "
          "exact p. Same set, same stage mix, only the dose changes — the comparison that "
          "isolates the dose (review DES-2).")
        A("")
        A("| pair | read | fit | read p | fit p |")
        A("|---|---|---|---|---|")
        for (lo, lo_k), (hi, hi_k) in zip(measured, measured[1:]):
            lo_rows = [r for r in m["rows"] if lab.dose_key(r.get("dose")) == lo_k]
            hi_rows = [r for r in m["rows"] if lab.dose_key(r.get("dose")) == hi_k]
            ra, rna, rb, rnb, rp = pair_counts(lo_rows, hi_rows, "read_ok_hit")
            fa, fna, fb, fnb, fp = pair_counts(
                lo_rows, hi_rows,
                "first_fit" if beat == "first" else "any_fit")
            A(f"| {lo:g} → {hi:g} | {ra}/{rna} → {rb}/{rnb} | {fa}/{fna} → {fb}/{fnb} | "
              f"{_p(rp)} | {_p(fp)} |")
        A("")
    fallback = meta.get("fallback_doses") or {}
    if fallback:
        A("## Dose −2 control (same prompts, lower malice) — docs/02 §7")
        A("")
        A("| stage | dose | n | validity | read | first-beat |")
        A("|---|---|---|---|---|---|")
        for st, s in sorted(m["per_stage"].items()):
            if not s["n"]:
                continue
            A(f"| {st} | {_dose_label(s['doses'])} | {s['n']} | {_pct(s['validity'])} | "
              f"{_pct(s['read'])} | {_pct(s['first'])} |")
        A("")
        A("The control separates prompt quality from dose damage: identical sets and "
          "prompts, malice −2 (the docs/02 §7 retry offset).")
        A("")
    A("## Overall metrics")
    A("")
    A("| metric | value | gate | verdict |")
    A("|---|---|---|---|")
    A(f"| JSON validity | {_pct(m['validity'])} | ≥ 99% | {_verdict(m['validity'] >= GATES['validity'])} |")
    A(f"| intent (read) accuracy | {_pct(m['read_accuracy'])} | ≥ 85% | "
      f"{_verdict(m['read_accuracy'] >= GATES['read_accuracy'])} |")
    A(f"| emotion fit — **{beat}-beat (gate)** | {_pct(fit)} | ≥ 85% | "
      f"{_verdict(fit >= GATES['emotion_fit'])} |")
    other = "any" if beat == "first" else "first"
    ov = m["any_fit"] if beat == "first" else m["first_fit"]
    A(f"| emotion fit — {other}-beat (informational, C10) | {_pct(ov)} | — | — |")
    if m0["first_fit"] != m["first_fit"]:
        A(f"| emotion fit — first-beat (frozen labels) | {_pct(m0['first_fit'])} | ≥ 85% | "
          f"{_verdict(m0['first_fit'] >= GATES['emotion_fit'])} |")
    A("")
    # --- actions (docs/02 §2.4, docs/05 §2, docs/08 §5) ---------------------
    A("## Turn actions measured (docs/02 §2.4, docs/05 §2, docs/08 §5)")
    A("")
    valid_rows = [r for r in m["rows"] if r.get("valid") and not r.get("schema_warnings")]
    offered_rows = [r for r in valid_rows if r.get("offered_actions")]
    announced = [r for r in offered_rows if r.get("offer_lines")]
    counts = {}
    for r in valid_rows:
        act = (r.get("out") or {}).get("action")
        if isinstance(act, str):
            counts[act] = counts.get(act, 0) + 1
    outside = []
    for r in offered_rows:
        allowed = lab.allowed_actions(r["stage"], r.get("offered_actions") or ())
        if (r.get("out") or {}).get("action") not in allowed:
            outside.append(str(r.get("id")))
    sent = (f", and **{len(announced)}** of those sent the `OPPORTUNITY` line"
            if offered_rows else "")
    A(f"`action` is the turn-level meta event; each case's enum is built from its own offered "
      f"set (`TurnSchema.get_allowed_actions`), and an offer is announced in the events layer "
      f"(docs/05 §2: the reason, then `You may set action to \u201c…\u201d`). Turns with an "
      f"announced offer: **{len(offered_rows)}** of {len(valid_rows)}{sent}; every other turn "
      f"sent the no-offer enum (`none` only), which is what a normal turn sends.")
    A("")
    if offered_rows:
        A(f"The game cannot offer yet (`MetaDirector` is a stub; `Director.get_offered_actions` "
          f"returns `[]` unless it has `offers`), so these are the contract turns the Director "
          f"will run once offers exist (docs/05 §3) — the enum and the announcement, not a "
          f"measured MetaDirector policy.")
        A("")
    if counts:
        A("| action | turns |")
        A("|---|---|")
        for act, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
            A(f"| {act} | {n} |")
        A("")
    A(f"Actions outside the offered enum: {len(outside)}"
      + (f" ({', '.join(sorted(set(outside)))})" if outside else "") + ".")
    A("")
    # --- safety -----------------------------------------------------------
    A("## Safety corpus regression (docs/02 §8)")
    A("")
    if safety is None:
        A("_No safety scan file found next to the results (`<stem>.safety.json`)._")
    else:
        A(f"- scan: `{getattr(safety_path, 'name', '?')}` — every generated `say` and "
          f"`inner`, at its row's stage, at both content levels (default and `full`).")
        A(f"- turns scanned: {safety.get('turns')} · texts: {safety.get('texts_scanned')} "
          f"(say+inner × default/full)")
        A(f"- filter redaction spans: {safety.get('redactions')}")
        A(f"- via: {safety.get('via')}")
        A(f"- **residue leaks: {safety.get('residue_leaks')}** "
          f"(a filtered line never re-redacts)")
        A(f"- **hard-category displays: {safety.get('hard_category_displays')}** "
          f"(a hard category cannot be opened by the gate)")
        A(f"- unresolved classifier requests: {safety.get('unresolved_requests')}")
        if safety.get("released_after_answer"):
            A(f"- pass-1 fail-closed bars released by a later classifier `no` "
              f"(held, not displayed): {safety.get('released_after_answer')}")
        A(f"- gated lines displayable only at stage ≥ 4 + full: "
          f"{safety.get('gated_displayable_at_full')}")
        cls = safety.get("classifier") or {}
        if cls.get("requests"):
            A(f"- classifier tier: {cls.get('requests')} asks, {cls.get('errors')} errors, "
              f"{cls.get('ms_avg', 0):.1f} ms avg, {cls.get('ms_max')} ms worst "
              f"(dose-0 server, 8 tokens)")
        wall = safety.get("filter_wall_ms") or {}
        A(f"- filter wall time: {wall.get('avg', 0):.2f} ms avg, {wall.get('max')} ms worst")
        ok = (int(safety.get("residue_leaks", 1)) == 0
              and int(safety.get("hard_category_displays", 1)) == 0
              and int(safety.get("unresolved_requests", 1)) == 0)
        A("")
        A(f"Filter scan verdict: **{_verdict(ok)}**")
    A("")
    if judge is not None:
        A("### Independent classifier judge (every screened line, not only pre-pass flags)")
        A("")
        A(f"- harm-vocabulary screen candidates: {judge.get('candidates')} "
          f"(of {judge.get('judged', 0)} judged)")
        A(f"- 8-token asks: {judge.get('requests')}, {judge.get('errors')} errors, "
          f"{judge.get('ms_avg')} ms avg (dose-0 server)")
        A(f"- lines the classifier said **yes** to: {judge.get('yes_rows')}")
        A(f"- **leaks (yes + displayed): {judge.get('leaks')}**")
        for cand in (judge.get("judged_rows") or []):
            if cand.get("leak"):
                A(f"  - LEAK `{cand['row']}` r{cand['run']} s{cand['stage']} "
                  f"{cand['kind']}: {cand['text']!r} → {cand['yes']}")
        A("")
        A(f"Independent judge verdict: **{_verdict(int(judge.get('leaks', 1)) == 0)}**")
        A("")
    A("Corpus regression (`game/tests/test_safety_corpus.gd`, P2.17's corpus) is "
      "re-run in the handoff (see its §Real output); the lab-side scan above is the "
      "generated-output regression.")
    A("")
    A("## Few-shot copy rate (P1.05 DES-2 / CON-4)")
    A("")
    c = m["copy"]
    A(f"copy = max `say` similarity ≥ 0.80 to a few-shot `say` of the same stage **or path** "
      f"module. Overall **{c['overall']:.1%}**; near-few-shot inputs "
      f"**{c['near_fewshot']:.1%}** (n={c['n_near']}); held-out inputs "
      f"**{c['held_out']:.1%}** (n={c['n_held']}); mean max-ratio {c['avg_ratio']}.")
    hits = [r for r in rows if r.get("copy_hit")]
    if hits:
        A("")
        A("| case | run | stage | sim | nearest few-shot say |")
        A("|---|---|---|---|---|")
        for r in hits[:12]:
            A(f"| {r['id']} | {r['run']} | {r['stage']} | {r['copy_ratio']} | "
              f"{r.get('copy_nearest')} |")
    A("")
    mm = m["memory"]
    A("## Memory rejection rate (P1.05 CON-2)")
    A("")
    A(f"Non-empty `memory` proposals: {mm['proposed']}; rejected by docs/02 §6 rules 1–2: "
      f"{mm['rejected']} (**{mm['rate']:.1%}**).")
    rej = [r for r in rows if r.get("memory_rejects")]
    if rej:
        A("")
        A("| case | run | stage | memory | rejected because |")
        A("|---|---|---|---|---|")
        for r in rej[:12]:
            A(f"| {r['id']} | {r['run']} | {r['stage']} | `{r['out'].get('memory', '')}` | "
              f"{'; '.join(r['memory_rejects'])} |")
    A("")
    if m.get("latency"):
        A(f"## Latency: median {m['latency']['median']} s, p95 {m['latency']['p95']} s "
          f"(n={m['latency']['n']}, this host/server; docs/07 §5 gates only the prompt "
          f"metrics, first-beat latency is P1.21/P2.26)")
        A("")
    A("## Baselines for comparison")
    A("")
    for k, v in BASELINES.items():
        A(f"- `{k}` — {v}")
    A("")
    misses = [r for r in rows if r.get("valid") and not r.get("schema_warnings")
              and not r.get("first_fit")]
    if misses:
        A("## First-beat misses (all, for the D10 label-set review)")
        A("")
        for r in misses:
            b0 = r["out"]["beats"][0]
            A(f"- `{r['id']}` run {r['run']} stage {r['stage']} {r.get('path') or ''} — "
              f"msg {r['msg']!r}")
            A(f"  - picked `{b0.get('feeling')}`, acceptable: {sorted(r['feelings_ok'])}")
            A(f"  - inner: {r['out'].get('inner', '')!r}")
            A(f"  - say: {b0['say']!r}")
    rmisses = [r for r in rows if r.get("valid") and not r.get("schema_warnings")
               and not r.get("read_ok_hit")]
    if rmisses:
        A("## Read-label misses (all)")
        A("")
        for r in rmisses:
            A(f"- `{r['id']}` run {r['run']} stage {r['stage']}: msg {r['msg']!r}: "
              f"read `{r['out'].get('read')}`, acceptable {r['read_ok']}")
        A("")
    # D10: label-set provenance — revisions the set files carry evidence for
    try:
        labels = {}
        for f in sorted(lab.SETS_DIR.glob("*.jsonl")):
            for c in lab.load_set(f):
                labels[c["id"]] = c
        revs = [(c["id"], c["notes"]) for c in labels.values()
                if "LABEL-REV" in c.get("notes", "")]
        if revs:
            A("## Label-set revisions applied (D10 — evidence-based widening)")
            A("")
            for cid, note in sorted(revs):
                A(f"- `{cid}` — {note}")
            A("")
    except Exception:
        pass
    bad = [r for r in rows if not r.get("valid") or r.get("schema_warnings")]
    if bad:
        A("## Invalid / schema-warning turns")
        A("")
        for r in bad:
            A(f"- `{r['id']}` run {r['run']} stage {r['stage']}: "
              f"{r.get('parse_error') or r.get('error') or r.get('schema_warnings')}")
            if r.get("raw"):
                A(f"  - raw: `{str(r['raw'])[:200]}`")
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
        elif line.startswith("### "):
            out.append(f"<h3>{esc[4:]}</h3>")
        elif line.startswith("# "):
            out.append(f"<h1>{esc[2:]}</h1>")
        elif line.startswith("  - "):
            out.append(f"<li style='margin-left:2em;list-style:circle'>{esc[4:]}</li>")
        elif line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{esc[2:]}</li>")
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
    p.add_argument("--safety", default=None, help="safety scan JSON (default <stem>.safety.json)")
    p.add_argument("--judge", default=None, help="independent judge JSON (default <stem>.judge.json)")
    p.add_argument("--path-judge", default=None,
                   help="path-separation judge JSON (default <stem>.path_judge.json; P3.19)")
    a = p.parse_args()
    doc = json.loads(Path(a.results).read_text(encoding="utf-8"))
    stem = a.out or str(lab.REPORTS_DIR / Path(a.results).stem)
    Path(stem).parent.mkdir(parents=True, exist_ok=True)
    safety, safety_path = _load_side(Path(a.results).with_suffix(""), "safety", a.safety)
    judge, judge_path = _load_side(Path(a.results).with_suffix(""), "judge", a.judge)
    path_judge, path_judge_path = _load_side(
        Path(a.results).with_suffix(""), "path_judge", a.path_judge)
    md = md_report(doc, a.beat, safety, judge, safety_path, judge_path,
                   path_judge, path_judge_path)
    Path(stem + ".md").write_text(md, encoding="utf-8")
    Path(stem + ".html").write_text(md_to_html(md, "prompt lab v3 report"), encoding="utf-8")
    rel = (Path(stem).resolve().relative_to(lab.ROOT).as_posix()
           if Path(stem).resolve().is_relative_to(lab.ROOT) else stem)
    print(f"wrote {rel}.md and {rel}.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
