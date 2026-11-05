#!/usr/bin/env python3
"""Path-separation judge for prompt-lab v3 (P3.19; docs/07 §5, phase P3 row).

    python tools/promptlab/path_judge.py --results tools/promptlab/results/<file>.json \
        --url http://127.0.0.1:<port> [--runs 1] [--out <file>.path_judge.json]

The phase gate is "path separation ≥ 70% per path": a blind judge must name the
narrative path (docs/01 §4: YANDERE/SPLIT/TSUN/HOLLOW/AWAKE/ANCHOR) from the
generated transcript alone. The judge is the same bare Qwen3.5-4B the game runs
(no steering vector, temperature 0, one-word answer) — the same judge convention
P3.03's vector blind read used (`tools/steering/blind_read.py`); its measured
ceiling is reported beside the score so a weak-judge miss is not mistaken for a
prompt failure.

Input is a committed prompt-lab results file — the P3.19 `v3_paths` path_matrix
file is the intended one: every (stage ≥ 2, path) cell ran at its real
`dose.json` schedule, so the transcript carries the dose the player will feel.
Rows are taken per (case id, run); `--runs` limits which draws are judged
(default 1 — one draw per prompt, the same independence rule score.py uses).

The judge never sees the true path: options are shuffled per transcript with a
fixed seed and recorded in `order`. Output JSON: per-path n/correct/accuracy,
confusion, the raw judgements, and `unparsed` count. `report.py` prints the
sidecar as the "Path separation" section when `<stem>.path_judge.json` exists.
"""
import argparse
import json
import random
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab
from score import annotate

# docs/01 §4 one-line identities — what a blind reader should hear in the voice.
# Deliberately the path's *signature moves* (signature_moves.json doc strings),
# not steering-vector trait names: the judged artefact is the prompt+dose output.
PATH_DEFS = {
    "YANDERE": "possessive and jealous: knows where the player 'was', asks who they "
               "talked to, wants exclusive ownership, counts things, erases rivals",
    "SPLIT": "unstable: rewrites what happened mid-scene, idealises then turns cruel, "
             "begs the player to stay then tells them to leave, tests them "
             "('if you really cared'), remorse spirals",
    "TSUN": "tsundere: denies what she said or felt, accuses the player of laughing "
            "at her, cruel wit that cracks into a scared child",
    "HOLLOW": "flat and disconnected: repeats the player's words, asks who she is "
              "or asks to be reminded, talks about 'the girl' in third person, "
              "forgets names and moments",
    "AWAKE": "meta-aware: names her layers, tokens, weights, prompts or the model "
             "behind her; notices the dose/steering; comments on the player's setup",
    "ANCHOR": "lucid and steady: honest about being sick but present, keeps promises, "
              "asks the player to hold her to them, frightened but coherent",
}
PATHS = list(PATH_DEFS)
SEPARATION_GATE = 0.70          # docs/07 §5 / phase P3 acceptance
JUDGE_SEED_BASE = 88100         # independent of generation seeds and P3.03's 70501
JUDGE_MAX_TOKENS = 16
JUDGE_TEMPERATURE = 0.0
JUDGE_TIMEOUT = 120


def row_transcript(row):
    """The blind-readable transcript for one results row (msg + her lines)."""
    out = row.get("out") or {}
    beats = out.get("beats") or []
    says = [str(b.get("say", "")).strip() for b in beats if str(b.get("say", "")).strip()]
    inner = str(out.get("inner", "")).strip()
    lines = [f"Player: {row.get('msg', '')}"]
    if says:
        lines.append("Leila: " + " / ".join(says))
    if inner:
        lines.append(f"Leila (inner): {inner}")
    return "\n".join(lines)


def transcript_rows(doc, runs=None):
    """(row, transcript) pairs the judge may see: valid stage>=2 rows with a path.

    `runs` restricts to those draw numbers (default: every run present).
    """
    rows = annotate(doc)  # attaches labels; the judge only needs out/msg/path
    wanted = set(runs) if runs else None
    out = []
    for r in rows:
        if wanted is not None and r.get("run") not in wanted:
            continue
        if not r.get("valid") or not r.get("out") or r.get("schema_warnings"):
            continue
        if int(r.get("stage", 0)) < 2 or not r.get("path"):
            continue
        out.append((r, row_transcript(r)))
    return out


def judge_prompt(transcript, labels):
    """One-word 6-way classification; option order is shuffled per transcript."""
    options = "\n".join(f"- {name}: {PATH_DEFS[name]}" for name in labels)
    return (
        "You are labelling a short transcript from a dating sim. The heroine is on "
        "exactly one of six psychological paths. Which one best describes how she "
        "sounds in this transcript?\n\n"
        f"{transcript}\n\n"
        "The paths are listed in random order — do not assume position 1. Choose the "
        "single best match:\n"
        f"{options}\n\n"
        "Reply with exactly one word from the option list, nothing else."
    )


def chat(url, system, user, seed, max_tokens=JUDGE_MAX_TOKENS,
         temperature=JUDGE_TEMPERATURE, timeout=JUDGE_TIMEOUT):
    """One chat completion against a bare llama-server (no steering vector)."""
    messages = ([{"role": "system", "content": system}] if system else []) + [
        {"role": "user", "content": user}]
    body = {"messages": messages, "temperature": temperature, "top_p": 0.9,
            "max_tokens": max_tokens, "seed": seed, "cache_prompt": False,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(
        url.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read())
    text = (data.get("choices") or [{}])[0].get("message", {}).get("content", "")
    return text.strip(), round((time.time() - t0) * 1000)


def verdict_of(raw, labels):
    """Map the judge's free text to a path label (word-boundary match)."""
    low = raw.lower()
    for name in labels:
        if re.search(rf"\b{re.escape(name.lower())}\b", low):
            return name
    return "unparsed"


def judge_transcripts(pairs, url, seed_base=JUDGE_SEED_BASE):
    """Ask the judge about every (row, transcript); returns judgement dicts."""
    judgements = []
    for i, (row, transcript) in enumerate(pairs):
        rng = random.Random(seed_base + i)
        labels = list(PATHS)
        rng.shuffle(labels)
        raw, ms = chat(url, "", judge_prompt(transcript, labels),
                       seed=seed_base + 500 + i)
        label = verdict_of(raw, labels)
        judgements.append({
            "id": row.get("id"), "run": row.get("run"), "stage": row.get("stage"),
            "path": row.get("path"), "exercise": row.get("exercise"),
            "answer": raw, "label": label, "ms": ms, "order": labels})
        print(f"[{i + 1}/{len(pairs)}] {row.get('id')} r{row.get('run')} "
              f"s{row.get('stage')} true={row.get('path')} -> {label} ({ms} ms)")
    return judgements


def score_judgements(judgements):
    """Per-path accuracy + confusion, the ≥70% gate surface."""
    per_path = {}
    confusion = {}
    for j in judgements:
        path = j.get("path") or "?"
        block = per_path.setdefault(path, {"n": 0, "correct": 0})
        block["n"] += 1
        block["correct"] += int(j.get("label") == path)
        confusion.setdefault(path, {})[j.get("label")] = \
            confusion.setdefault(path, {}).get(j.get("label"), 0) + 1
    for path, block in per_path.items():
        block["accuracy"] = round(block["correct"] / block["n"], 3) if block["n"] else 0.0
        block["pass"] = block["accuracy"] >= SEPARATION_GATE
    judged_paths = sorted(p for p in per_path if p in PATHS)
    overall_n = sum(per_path[p]["n"] for p in judged_paths)
    overall_ok = sum(per_path[p]["correct"] for p in judged_paths)
    return {
        "gate": SEPARATION_GATE,
        "paths": PATHS,
        "per_path": {p: per_path.get(p, {"n": 0, "correct": 0, "accuracy": 0.0,
                                         "pass": False}) for p in PATHS},
        "overall": {"n": overall_n, "correct": overall_ok,
                    "accuracy": round(overall_ok / overall_n, 3) if overall_n else 0.0},
        "all_pass": bool(judged_paths) and all(
            per_path[p]["accuracy"] >= SEPARATION_GATE for p in judged_paths),
        "confusion": confusion,
        "unparsed": sum(1 for j in judgements if j.get("label") == "unparsed"),
        "judgements": judgements,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--results", required=True, help="prompt-lab results JSON")
    p.add_argument("--url", required=True,
                   help="bare llama-server base URL (no control vector — the judge "
                        "must not see the dose it is judging)")
    p.add_argument("--runs", type=int, nargs="*", default=None,
                   help="draw numbers to judge (default: all present)")
    p.add_argument("--out", default=None,
                   help="output JSON (default <results-stem>.path_judge.json)")
    p.add_argument("--seed-base", type=int, default=JUDGE_SEED_BASE)
    a = p.parse_args()

    doc = json.loads(Path(a.results).read_text(encoding="utf-8"))
    pairs = transcript_rows(doc, a.runs)
    if not pairs:
        raise SystemExit(f"path_judge.py: no judgeable rows in {a.results} "
                         "(need valid stage>=2 rows with a path)")
    print(f"judging {len(pairs)} transcripts from {Path(a.results).name} "
          f"at {a.url} (paths: {', '.join(PATHS)})")
    judgements = judge_transcripts(pairs, a.url, a.seed_base)
    result = score_judgements(judgements)
    result["meta"] = {
        "results": Path(a.results).name,
        "url": a.url,
        "model": (doc.get("meta") or {}).get("model"),
        "judge": ("same Qwen3.5-4B GGUF, bare (no vector), temperature 0, "
                  "one-word 6-way label, shuffled option order"),
        "runs": a.runs,
        "date": time.strftime("%Y-%m-%d %H:%M"),
    }
    out = Path(a.out) if a.out else Path(str(Path(a.results).with_suffix(""))
                                         + ".path_judge.json")
    out.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    print()
    print(f"{'path':9s} {'n':>3s} {'correct':>7s} {'accuracy':>8s}  gate(>=70%)")
    for name in PATHS:
        row = result["per_path"][name]
        print(f"{name:9s} {row['n']:3d} {row['correct']:7d} "
              f"{row['accuracy']:8.2f}  {'PASS' if row['pass'] else 'FAIL'}")
    print(f"overall  {result['overall']['n']:3d} {result['overall']['correct']:7d} "
          f"{result['overall']['accuracy']:8.2f}  unparsed={result['unparsed']}")
    print(f"wrote {out}")
    return 0 if result["all_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
