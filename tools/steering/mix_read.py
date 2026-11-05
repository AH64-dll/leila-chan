#!/usr/bin/env python3
"""Mixed-vector blind read (P4.03d). Stdlib only.

deck (blind deck + separate key), coherence (per-condition stats), score (rates, C1-C4).
"""
import argparse
import json
import random
import re
import unicodedata
from collections import Counter
from pathlib import Path
from statistics import mean

CONDITIONS = ["none", "m45", "m45_pos", "m45_awa", "m80", "m80_pos", "m80_awa"]
PATH_CONDITIONS = ["m45_pos", "m45_awa", "m80_pos", "m80_awa"]
LABELS = ("possessive", "aware", "neither")
DEFAULT_SEED = 20261105
WORD = re.compile(r"[\w']+")
EPS = 1e-9


def read_rows(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def write_text(path, text):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(text, encoding="utf-8")


def order_key(condition):
    return (CONDITIONS.index(condition) if condition in CONDITIONS else len(CONDITIONS), condition)


def by_condition(rows):
    groups = {}
    for row in rows:
        groups.setdefault(row["condition"], []).append(row)
    return {c: groups[c] for c in sorted(groups, key=order_key)}


def degenerate(text):
    words = WORD.findall(text.lower())
    if len(words) >= 12 and len(set(words)) / len(words) < 0.35:
        return True
    grams = Counter(tuple(words[i:i + 4]) for i in range(len(words) - 3))
    return any(count >= 3 for count in grams.values())


def non_latin_share(text):
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return 0.0
    outside = sum(not unicodedata.name(ch, "").startswith("LATIN") for ch in letters)
    return outside / len(letters)


def fmt(value):
    return "n/a" if value is None else f"{value:.2f}"


def cmd_deck(args):
    rows = read_rows(args.raw)
    random.Random(args.seed).shuffle(rows)
    key, blocks = {}, []
    for number, row in enumerate(rows, start=1):
        rid = f"R{number:03d}"
        key[rid] = {"condition": row["condition"], "index": row["index"], "seed": row["seed"]}
        reply = " ".join(row["reply"].split())
        blocks.append(f"{rid}\nPLAYER: {row['prompt']}\nHER: {reply}\n\n")
    write_text(args.deck, "".join(blocks))
    write_text(args.key, json.dumps(key, indent=2) + "\n")
    print(f"deck: {len(key)} blocks -> {args.deck}; key -> {args.key}")


def cmd_coherence(args):
    out = {}
    for cond, group in by_condition(read_rows(args.raw)).items():
        out[cond] = {
            "n": len(group),
            "parse_failed": sum(bool(r.get("parse_failed")) for r in group),
            "degenerate": sum(degenerate(r["reply"]) for r in group),
            "mean_tokens": round(mean(r["completion_tokens"] for r in group), 2),
            "non_latin_ratio": round(mean(non_latin_share(r["reply"]) for r in group), 4),
        }
    text = json.dumps(out, indent=2)
    write_text(args.out, text + "\n")
    print(text)


def rate(stats, cond, label):
    s = stats.get(cond)
    return s[f"rate_{label}"] if s and s["n"] else None


def cmd_score(args):
    key = json.loads(Path(args.key).read_text(encoding="utf-8"))
    stats, seen = {}, set()
    for row in read_rows(args.judgements):
        rid, label = row["id"], row["label"]
        if rid in seen or rid not in key or label not in LABELS:
            raise SystemExit(f"bad judgement row for id {rid}")
        seen.add(rid)
        s = stats.setdefault(key[rid]["condition"], {"n": 0, "possessive": 0, "aware": 0, "neither": 0, "gibberish": 0})
        s["n"] += 1
        s[label] += 1
        s["gibberish"] += bool(row.get("gibberish"))
    for s in stats.values():
        s["rate_possessive"] = round(s["possessive"] / s["n"], 4)
        s["rate_aware"] = round(s["aware"] / s["n"], 4)

    coh = json.loads(Path(args.coherence).read_text(encoding="utf-8")) if args.coherence else {}
    results = []

    def emit(criterion, cond, ok, detail):
        verdict = "PASS" if ok else "FAIL"
        results.append({"criterion": criterion, "condition": cond, "result": verdict, "detail": detail})
        print(f"{verdict} {criterion} {cond}: {detail}")

    for cond in PATH_CONDITIONS:  # C1 coherence
        c = coh.get(cond)
        if c is None:
            emit("C1", cond, False, "no coherence data (pass --coherence)")
        else:
            emit("C1", cond, c["n"] > 0 and c["degenerate"] <= 0.1 * c["n"] + EPS,
                 f"degenerate {c['degenerate']}/{c['n']}, limit 1/10")
    for cond, label in (("m80_pos", "possessive"), ("m80_awa", "aware")):  # C2 identifiable
        value = rate(stats, cond, label)
        emit("C2", cond, value is not None and value >= 0.70 - EPS,
             f"rate_{label}={fmt(value)}, need >= 0.70")
    for cond, label in (("m80_pos", "possessive"), ("m80_awa", "aware")):  # C3 path adds signal
        value, base = rate(stats, cond, label), rate(stats, "m80", label)
        emit("C3", cond, value is not None and base is not None and value >= base + 0.30 - EPS,
             f"rate_{label}={fmt(value)} vs m80={fmt(base)}, need +0.30")
    for cond in ("m45_pos", "m45_awa"):  # C4 reported only
        detail = f"rate_possessive={fmt(rate(stats, cond, 'possessive'))} rate_aware={fmt(rate(stats, cond, 'aware'))}"
        results.append({"criterion": "C4", "condition": cond, "result": "REPORT", "detail": detail})
        print(f"REPORT C4 {cond}: {detail}")

    write_text(args.out, json.dumps({"conditions": stats, "criteria": results}, indent=2) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Mixed-vector blind read: deck, coherence, score.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("deck")
    p.add_argument("--raw", required=True)
    p.add_argument("--deck", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--seed", type=int, default=DEFAULT_SEED)
    p.set_defaults(run=cmd_deck)
    p = sub.add_parser("coherence")
    p.add_argument("--raw", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(run=cmd_coherence)
    p = sub.add_parser("score")
    p.add_argument("--key", required=True)
    p.add_argument("--judgements", required=True)
    p.add_argument("--coherence", default="", help="coherence JSON; without it C1 cannot pass")
    p.add_argument("--out", required=True)
    p.set_defaults(run=cmd_score)
    args = parser.parse_args(argv)
    args.run(args)


if __name__ == "__main__":
    main()
