#!/usr/bin/env python3
"""Compare prefix-cache runs written by native/tests/cache_scene.gd.

Reads every *.jsonl file in --dir. Prints, per configuration, latency and cache
statistics over turns 2-8 (turn 1 is cold and shown on its own line), then for
each cache=1 run the number of byte-identical turns against its cache=0 twin
(same ubatch, dose, dose_from and temp). Stdlib only.

Usage: python3 -I tools/promptlab/cache_compare.py --dir DIR
"""
import argparse
import glob
import json
import math
import os
import sys

WARM_FROM = 2  # turn 1 of every process is cold and excluded from the means


def load_rows(directory):
    rows = []
    for path in sorted(glob.glob(os.path.join(directory, "*.jsonl"))):
        with open(path, encoding="utf-8") as handle:
            rows.extend(json.loads(line) for line in handle if line.strip())
    return rows


def config_key(row):
    return (row["cache"], row["ubatch"], row["dose"], row["dose_from"], row["temp"])


def describe(key):
    cache, ubatch, dose, dose_from, temp = key
    frm = "-" if dose_from is None else dose_from
    return f"cache={cache} ubatch={ubatch} dose={dose} dose_from={frm} temp={temp}"


def sort_key(key):
    cache, ubatch, dose, dose_from, temp = key
    return (str(temp), dose, str(dose_from), -ubatch, cache)


def mean(values):
    return sum(values) / len(values) if values else float("nan")


def p90(values):
    if not values:
        return float("nan")
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.9 * len(ordered)) - 1)]


def column(rows, name):
    return [row[name] for row in rows]


def summarise(runs):
    print(f"Per configuration, turns {WARM_FROM}-8 (turn 1 is cold)")
    for key in sorted(runs, key=sort_key):
        rows = sorted(runs[key], key=lambda row: row["turn"])
        warm = [row for row in rows if row["turn"] >= WARM_FROM]
        cold = [row for row in rows if row["turn"] == 1]
        first_say = column(warm, "first_say_ms")
        prompt_ms = column(warm, "prompt_ms")
        print(describe(key))
        print(f"  first_say_ms mean {mean(first_say):.0f} p90 {p90(first_say):.0f}"
              f" | prompt_ms mean {mean(prompt_ms):.0f} p90 {p90(prompt_ms):.0f}")
        print(f"  reused_tokens mean {mean(column(warm, 'cache_reused_tokens')):.0f}"
              f" | prompt_tokens mean {mean(column(warm, 'prompt_tokens')):.0f}"
              f" | save_ms mean {mean(column(warm, 'cache_save_ms')):.1f}"
              f" | restore_ms mean {mean(column(warm, 'cache_restore_ms')):.1f}"
              f" | max_state_bytes {max(column(warm, 'cache_state_bytes'), default=-1)}")
        if cold:
            print(f"  turn 1 (cold): first_say_ms {cold[0]['first_say_ms']}"
                  f" prompt_ms {cold[0]['prompt_ms']}")


def texts(rows):
    return {row["turn"]: row["text"] for row in rows}


def compare(runs):
    print("Byte-identical text, cache=1 against its cache=0 twin")
    for key in sorted(runs, key=sort_key):
        if key[0] != 1:
            continue
        twin = (0,) + key[1:]
        if twin not in runs:
            print(f"{describe(key)}: no cache=0 twin")
            continue
        base, cached = texts(runs[twin]), texts(runs[key])
        turns = sorted(set(base) & set(cached))
        differ = [turn for turn in turns if base[turn] != cached[turn]]
        where = ", ".join(str(turn) for turn in differ) if differ else "none"
        print(f"{describe(key)}: identical {len(turns) - len(differ)}/{len(turns)} turns;"
              f" differ at turn(s) {where}")


def main():
    parser = argparse.ArgumentParser(description="Summarise cache_scene JSONL runs.")
    parser.add_argument("--dir", required=True, help="directory holding the *.jsonl runs")
    args = parser.parse_args()
    rows = load_rows(args.dir)
    if not rows:
        sys.exit(f"no JSONL rows in {args.dir}")
    runs = {}
    for row in rows:
        runs.setdefault(config_key(row), []).append(row)
    summarise(runs)
    print()
    compare(runs)


if __name__ == "__main__":
    main()
