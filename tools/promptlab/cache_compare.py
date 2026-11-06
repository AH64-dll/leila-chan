#!/usr/bin/env python3
"""Compare prefix-cache runs written by native/tests/cache_scene.gd.

Reads every *.jsonl file in --dir. Prints, per configuration, latency and cache
statistics over turns 2-8 (turn 1 is cold and shown on its own line), then for
each cache=1 run the number of byte-identical turns against its cache=0 twin
(same ubatch, dose, dose_from and temp). Stdlib only.

With --tiers, prints one Markdown table row per file instead (label = file name):
device, threads, first_say_ms mean and p90 over turns 2-8, turn 1 first_say_ms,
total_ms mean over turns 2-8, tok/s mean over turns 2-8, vm_hwm_kb from the last
row, and a status. Rows with an error are left out of the timing means.

Usage: python3 -I tools/promptlab/cache_compare.py --dir DIR [--tiers]
"""
import argparse
import glob
import json
import math
import os
import sys

WARM_FROM = 2  # turn 1 of every process is cold and excluded from the means
TURNS = 8


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


def load_file(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def is_ok(row):
    return row.get("turn", 0) >= 1 and "error" not in row


def fmt(value, digits=0):
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return "n/a"
    return f"{value:.{digits}f}"


def error_code(row):
    error = row.get("error", {})
    if isinstance(error, dict):
        return str(error.get("code", "unknown"))
    return str(error)


def tier_line(path):
    label = os.path.splitext(os.path.basename(path))[0]
    rows = sorted(load_file(path), key=lambda row: row["turn"])
    if not rows:
        return f"| {label} | - | - | - | - | - | - | - | - | no rows |"
    devices = "/".join(sorted({str(row.get("device", "-")) for row in rows}))
    threads = "/".join(sorted({str(row.get("n_threads", -1)) for row in rows}))
    ok_turns = [row for row in rows if is_ok(row)]
    warm_ok = [row for row in ok_turns if row["turn"] >= WARM_FROM]
    cold_ok = [row for row in ok_turns if row["turn"] == 1]
    first_say = column(warm_ok, "first_say_ms")
    total = column(warm_ok, "total_ms")
    toks = column(warm_ok, "tok_s")
    hwm_rows = [row for row in rows if "vm_hwm_kb" in row]
    hwm = hwm_rows[-1]["vm_hwm_kb"] if hwm_rows else None
    failed = [row for row in rows if row["turn"] >= 1 and not is_ok(row)]
    load_errors = [row for row in rows if row["turn"] == 0]
    if load_errors:
        status = f"load failed: {error_code(load_errors[0])}"
    elif failed:
        status = f"{len(ok_turns)}/{TURNS} turns ok; first error: {error_code(failed[0])}"
    elif len(ok_turns) < TURNS:
        status = f"{len(ok_turns)}/{TURNS} turns ok; rows missing (timeout?)"
    else:
        status = f"ok {len(ok_turns)}/{TURNS}"
    cold = fmt(cold_ok[0]["first_say_ms"]) if cold_ok else "n/a"
    return (f"| {label} | {devices} | {threads}"
            f" | {fmt(mean(first_say))} | {fmt(p90(first_say))} | {cold}"
            f" | {fmt(mean(total))} | {fmt(mean(toks), 1)} | {fmt(hwm)} | {status} |")


def tiers(directory):
    paths = sorted(glob.glob(os.path.join(directory, "*.jsonl")))
    if not paths:
        sys.exit(f"no JSONL files in {directory}")
    print("| Label | Device | Threads | first_say mean (ms) | first_say p90 (ms)"
          " | turn 1 first_say (ms) | total_ms mean | tok/s mean | vm_hwm_kb | Status |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for path in paths:
        print(tier_line(path))


def main():
    parser = argparse.ArgumentParser(description="Summarise cache_scene JSONL runs.")
    parser.add_argument("--dir", required=True, help="directory holding the *.jsonl runs")
    parser.add_argument("--tiers", action="store_true",
                        help="one Markdown row per file: device tiers, turns 2-8 means")
    args = parser.parse_args()
    if args.tiers:
        tiers(args.dir)
        return
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
