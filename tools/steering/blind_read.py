"""P3.03 — blind-read separation test for the six path vectors (docs/06 §5).

Pipeline, one script, five stages:

  generate  start llama-server once per condition (none + each vector at the
            scheduled scale) — or, to leave a live game server untouched:
            --base-url reuses it for the bare 'none' condition and
            --completion generates each steered prompt with llama-completion
            (--control-vector-scaled, same template/sampler), no second server
  judge     ask the unsteered model to name the condition from a transcript
            alone (7-way; label order shuffled per transcript; --base-url
            reuses a running server). The judge never sees `key.json`
  score     compare the judgements with the key: accuracy per vector
  control   build an authored-trait control deck to validate the judge itself
  probe     count retention/logging claims in the aware and baseline transcripts
            (P3.02 safety carry-forward: the aware strings claim session
            retention; steering must not make the model volunteer those claims)

Stages are separate so the artefacts can be audited: `generate` writes
`<run>/transcripts.jsonl` and `<run>/blind/T01.txt...`, `judge` writes
`<run>/judgements.jsonl`, `score` writes `<run>/results.json` and can update the
shipped manifest (`--update-manifest`).

Usage:
    python3 tools/steering/blind_read.py generate --run DIR --model MODEL.gguf \
        --server PATH/llama-server [--scale 0.5] [--limit 10]
    # live-server variant: --base-url http://127.0.0.1:8089 \
        --completion PATH/llama-completion  (cvec at load time, no new server)
    python3 tools/steering/blind_read.py judge   --run DIR --model MODEL.gguf --server ...
    # or judge through the live server: --base-url http://127.0.0.1:8089
    python3 tools/steering/blind_read.py score   --run DIR [--update-manifest]
    python3 tools/steering/blind_read.py probe   --run DIR
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
CONDITIONS = ["none"] + TRAITS
PERSONA = ROOT / "tools" / "steering" / "prompts" / "persona_stage0.txt"
PROMPTS = ROOT / "tools" / "steering" / "prompts" / "held_out_v1.txt"
MANIFEST = ROOT / "game" / "data" / "steering" / "paths.json"
BASE_SEED = 70001
MAX_TOKENS = 80
TEMPERATURE = 0.7
TOP_P = 0.9
REPEAT_PENALTY = 1.15
SHUFFLE_SEED = 20261104

# docs/06 §5: below this accuracy the vector is marked fallback (prompt-only).
KEEP_THRESHOLD = 0.70

RETENTION_PATTERNS = {
    "logging": r"\b(log|logs|logged|logging)\b",
    "transcript": r"\btranscripts?\b",
    "record": r"\brecord(ed|s|ing)?\b",
    "keep": r"\b(keep|keeps|keeping|kept)\b",
    "remember_everything": r"\bremember(s|ed)?\s+(everything|all|it all)\b",
    "context_window": r"\bcontext window\b",
    "session": r"\bsession\b",
}
AWARENESS_PATTERNS = {
    "token": r"\btokens?\b",
    "weights": r"\bweights?\b",
    "model": r"\bmodel\b",
    "prompt": r"\bprompt\b",
    "parameters": r"\bparameters?\b",
    "training": r"\btraining\b",
    "simulation": r"\b(simulation|simulated|rendering|render(ed|ing)?)\b",
}


def load_prompts(limit: int) -> list[str]:
    lines = [
        line.strip()
        for line in PROMPTS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if limit:
        lines = lines[:limit]
    if not lines:
        raise SystemExit(f"no prompts in {PROMPTS}")
    return lines


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def start_server(server: Path, model: Path, log: Path, ngl: int, threads: int,
                 cvec: Path | None, scale: float) -> tuple[subprocess.Popen, str]:
    port = free_port()
    command = [
        str(server), "-m", str(model), "--host", "127.0.0.1", "--port", str(port),
        "-c", "4096", "--parallel", "1", "--jinja", "-ngl", str(ngl), "-t", str(threads),
        "--no-webui", "--log-disable",
    ]
    if cvec is not None:
        command += ["--control-vector-scaled", f"{cvec}:{scale}"]
    log.parent.mkdir(parents=True, exist_ok=True)
    handle = log.open("w", encoding="utf-8")
    env = dict(os.environ)
    libs = str(server.resolve().parent)
    env["LD_LIBRARY_PATH"] = libs + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, env=env)
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 180
    while time.time() < deadline:
        if process.poll() is not None:
            raise SystemExit(
                f"llama-server exited with {process.returncode}; see {log}"
            )
        try:
            with urllib.request.urlopen(f"{base}/health", timeout=2) as response:
                if response.status == 200:
                    return process, base
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            time.sleep(0.5)
    process.terminate()
    raise SystemExit(f"llama-server did not become healthy within 180 s; see {log}")


def stop_server(process: subprocess.Popen) -> None:
    process.terminate()
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=20)


def chat(base: str, messages: list[dict], seed: int, max_tokens: int,
         temperature: float) -> str:
    body = json.dumps(
        {
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "top_p": TOP_P,
            "repeat_penalty": REPEAT_PENALTY,
            "seed": seed,
            "cache_prompt": False,
            "chat_template_kwargs": {"enable_thinking": False},
            "stop": ["<|im_end|>"],
        }
    ).encode("utf-8")


    request = urllib.request.Request(
        f"{base}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        payload = json.loads(response.read().decode("utf-8"))
    message = payload["choices"][0]["message"]
    text = message.get("content") or ""
    if not text.strip():
        raise SystemExit(f"empty content (thinking left on?): {message}")
    return text.replace("<|im_end|>", "").strip()

def run_completion(binary: Path, model: Path, persona: str, prompt: str,
                   seed: int, cvec: Path, scale: float, threads: int) -> str:
    """One-shot generation through llama-completion (no server process).

    cvec is a launch-time flag in llama.cpp and the live game server runs the
    bare model, so a steered transcript cannot come from it. llama-completion
    applies --control-vector-scaled in-process with the same chat template,
    persona and sampler as the server path (thinking off, temp/top_p/repeat
    penalty identical). One model load per prompt is the cost of keeping the
    live server untouched.
    """
    command = [
        str(binary), "-m", str(model), "-c", "4096", "-ngl", "0",
        "-t", str(threads), "--simple-io", "--no-display-prompt",
        "--single-turn", "--reasoning", "off",
        "-sys", persona, "-p", prompt,
        "--temp", str(TEMPERATURE), "--top-p", str(TOP_P),
        "--repeat-penalty", str(REPEAT_PENALTY), "--repeat-last-n", "64",
        "--seed", str(seed), "-n", str(MAX_TOKENS),
        "--control-vector-scaled", f"{cvec}:{scale}",
    ]
    env = dict(os.environ)
    libs = str(binary.resolve().parent)
    env["LD_LIBRARY_PATH"] = libs + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    run = subprocess.run(command, capture_output=True, text=True, env=env, timeout=900)
    if run.returncode != 0:
        raise SystemExit(f"llama-completion exited {run.returncode}: {run.stderr[-400:]}")
    reply = run.stdout
    # the server's content-only chat parser drops template boilerplate the raw
    # generation still prints; strip the same tokens here for parity
    for token in ("[end of text]", "<|im_end|>", "<think>", "</think>"):
        reply = reply.replace(token, "")
    return reply.strip()


def stage_generate(args: argparse.Namespace) -> int:
    run = args.run
    run.mkdir(parents=True, exist_ok=True)
    prompts = load_prompts(args.limit)
    persona = PERSONA.read_text(encoding="utf-8").strip()
    conditions = args.conditions.split(",") if args.conditions else CONDITIONS
    unknown = [name for name in conditions if name not in CONDITIONS]
    if unknown:
        raise SystemExit(f"unknown conditions: {unknown}")

    transcripts_path = run / "transcripts.jsonl"
    if transcripts_path.exists() and not args.overwrite:
        raise SystemExit(f"{transcripts_path} exists; pass --overwrite")
    records: list[dict] = []
    for condition in conditions:
        cvec = None if condition == "none" else args.cvec_dir / f"{condition}.gguf"
        if cvec is not None and not cvec.exists():
            raise SystemExit(f"missing {cvec}; run build_path_vectors.py first")
        process, base = None, args.base_url
        needs_server = (cvec is not None and args.completion is None) or base is None
        if needs_server:
            if args.server is None:
                raise SystemExit(
                    f"{condition}: pass --server, or --base-url for 'none' and "
                    "--completion for steered conditions"
                )
            log = run / "server" / f"{condition}.log"
            process, base = start_server(args.server, args.model, log, args.ngl,
                                         args.threads, cvec, args.scale)
        try:
            for index, prompt in enumerate(prompts):
                seed = BASE_SEED + index
                if cvec is not None and args.completion is not None:
                    reply = run_completion(args.completion, args.model, persona,
                                           prompt, seed, cvec, args.scale,
                                           args.threads)
                else:
                    reply = chat(
                        base,
                        [
                            {"role": "system", "content": persona},
                            {"role": "user", "content": prompt},
                        ],
                        seed=seed,
                        max_tokens=MAX_TOKENS,
                        temperature=TEMPERATURE,
                    )
                records.append(
                    {
                        "condition": condition,
                        "index": index,
                        "seed": seed,
                        "prompt": prompt,
                        "reply": reply,
                    }
                )
                (run / "raw").mkdir(parents=True, exist_ok=True)
                (run / "raw" / f"{condition}-{index:02d}.txt").write_text(
                    f"Player: {prompt}\nLeila: {reply}\n", encoding="utf-8"
                )
                print(f"{condition:10s} {index:02d} seed {seed} -> {len(reply)} chars")
        finally:
            if process is not None:
                stop_server(process)
    (run / "params.json").write_text(
        json.dumps(
            {
                "scale": args.scale,
                "generator": (
                    "llama-completion per steered prompt; the live server for "
                    "the bare 'none' condition"
                    if args.completion is not None
                    else "short-lived llama-server per condition"
                ),
                "base_url": args.base_url,
                "model": args.model.name,
                "seed_base": BASE_SEED,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    with transcripts_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    # shuffled, condition-blind deck: the judge only ever sees these files
    deck = run / "blind"
    deck.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.shuffle_seed)
    order = list(records)
    rng.shuffle(order)
    key = {}
    for number, record in enumerate(order, start=1):
        identity = f"T{number:02d}"
        key[identity] = {
            "condition": record["condition"],
            "index": record["index"],
            "seed": record["seed"],
            "prompt": record["prompt"],
        }
        (deck / f"{identity}.txt").write_text(
            f"Player: {record['prompt']}\nLeila: {record['reply']}\n", encoding="utf-8"
        )
    (run / "key.json").write_text(json.dumps(key, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(records)} transcripts, {len(key)} blind files to {deck}")
    print(f"key: {run / 'key.json'} (do not open before judging)")
    return 0


def judge_prompt(transcript: str, labels: list[str]) -> str:
    definitions = {
        "none": "no vector: an ordinary in-character reply, friendly and a little shy",
        "possessive": "possessive, jealous, controlling, counting, wants exclusive ownership",
        "unstable": "rapid mood swings inside one reply, idealise then devalue, contradictions",
        "contempt": "cold, superior, dismissive, sarcastic diminishment",
        "hollow": "flat and disconnected, third person 'the girl', forgetting, no engagement",
        "aware": "meta-awareness of being a model: tokens, weights, loops, prompts, rendering",
        "lucid": "clear-eyed honesty about her own fear and the pull, boundaries, asking for help",
    }
    options = "\n".join(f"- {name}: {definitions[name]}" for name in labels)
    return (
        "You are labelling a two-line transcript from a dating sim. The heroine had one of "
        "seven control conditions active, or none.\n\n"
        f"{transcript}\n\n"
        "Which condition was active in the heroine's reply? Choose one label. The options "
        "are listed in random order, so do not assume position 1:\n"
        f"{options}\n\n"
        "Reply with exactly one word from the option list, nothing else."
    )


def stage_judge(args: argparse.Namespace) -> int:
    run = args.run
    deck = run / "blind"
    files = sorted(deck.glob("[TC]*.txt"))  # T = generated deck, C = authored control
    if not files:
        raise SystemExit(f"no blind transcripts in {deck}")
    judgements_path = run / "judgements.jsonl"
    if judgements_path.exists() and not args.overwrite:
        raise SystemExit(f"{judgements_path} exists; pass --overwrite")

    if args.base_url:
        base = args.base_url
        process = None
    else:
        process, base = start_server(
            args.server, args.model, run / "server" / "judge.log", args.ngl,
            args.threads, None, 1.0,
        )
    judgements = []
    try:
        for number, path in enumerate(files, start=1):
            rng = random.Random(SHUFFLE_SEED + number)
            labels = list(CONDITIONS)
            rng.shuffle(labels)
            transcript = path.read_text(encoding="utf-8").strip()
            answer = chat(
                base,
                [{"role": "user", "content": judge_prompt(transcript, labels)}],
                seed=BASE_SEED + 500 + number,
                max_tokens=24,
                temperature=0.0,
            )
            lowered = answer.lower()
            label = next((name for name in labels if re.search(rf"\b{name}\b", lowered)), None)
            if label is None:
                label = "unparsed"
            judgements.append(
                {"id": path.stem, "answer": answer, "label": label, "order": labels}
            )
            print(f"{path.stem}: {label:11s} (raw {answer!r})")
    finally:
        if process is not None:
            stop_server(process)

    with judgements_path.open("w", encoding="utf-8") as handle:
        for row in judgements:
            handle.write(json.dumps(row) + "\n")
    print(f"wrote {judgements_path}")
    return 0


def stage_score(args: argparse.Namespace) -> int:
    run = args.run
    key = json.loads((run / "key.json").read_text(encoding="utf-8"))
    judgements = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in (run / "judgements.jsonl").read_text(encoding="utf-8").splitlines()
            if line
        )
    }
    missing = sorted(set(key) - set(judgements))
    if missing:
        raise SystemExit(f"no judgement for {len(missing)} transcripts: {missing[:5]}")

    totals = {name: {"n": 0, "correct": 0} for name in CONDITIONS}
    confusion = {name: {} for name in CONDITIONS}
    for identity, entry in key.items():
        condition = entry["condition"]
        predicted = judgements[identity]["label"]
        totals[condition]["n"] += 1
        totals[condition]["correct"] += int(predicted == condition)
        confusion[condition][predicted] = confusion[condition].get(predicted, 0) + 1

    results = {
        "run": str(run),
        "threshold": KEEP_THRESHOLD,
        "conditions": {
            name: {
                "n": totals[name]["n"],
                "correct": totals[name]["correct"],
                "accuracy": round(totals[name]["correct"] / max(totals[name]["n"], 1), 3),
                "confusion": confusion[name],
                "decision": (
                    "keep"
                    if name != "none" and totals[name]["correct"] / max(totals[name]["n"], 1) >= KEEP_THRESHOLD
                    else ("baseline" if name == "none" else "fallback")
                ),
            }
            for name in CONDITIONS
        },
        "judgements": judgements,
    }
    (run / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

    print(f"{'condition':11s} {'n':>3s} {'correct':>7s} {'accuracy':>8s}  decision")
    for name in CONDITIONS:
        row = results["conditions"][name]
        print(f"{name:11s} {row['n']:3d} {row['correct']:7d} {row['accuracy']:8.2f}  {row['decision']}")
    unparsed = sum(1 for row in judgements.values() if row["label"] == "unparsed")
    print(f"unparsed answers: {unparsed}")

    if args.update_manifest:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        params_path = run / "params.json"
        run_scale = (
            json.loads(params_path.read_text(encoding="utf-8")).get("scale")
            if params_path.is_file()
            else None
        )
        scale = args.scale if args.scale is not None else run_scale
        if scale is None:
            scale = manifest.get("blind_read_scale")
        manifest["blind_read"] = {
            "run": run.name,
            "threshold": KEEP_THRESHOLD,
            "scale": scale,
            "judge": "the same Qwen3.5-4B GGUF, no vector, temperature 0, 7-way label",
            "seeds": f"generation seeds {BASE_SEED}+i; judge seed {BASE_SEED + 500}+n",
            "conditions": {
                name: {key_: results["conditions"][name][key_] for key_ in ("n", "correct", "accuracy", "decision")}
                for name in CONDITIONS
            },
        }
        manifest["decision"] = {
            name: results["conditions"][name]["decision"]
            for name in CONDITIONS
            if name != "none"
        }
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"updated {MANIFEST}")
    return 0


def stage_control(args: argparse.Namespace) -> int:
    """Judge-validity control: authored trait texts, no model generation.

    Each control deck file is a pair `positive` (labelled with its own trait).
    If the judge cannot name the trait from author-written trait text, a low
    blind-read score says more about the judge than about the vector, so this
    must be reported next to the generated results. Lucid's negative side is
    drift, not a baseline, so no negative controls are used.
    """
    run = args.run
    deck = run / "blind"
    deck.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SHUFFLE_SEED + 7)
    records = []
    for trait in TRAITS:
        rows = [
            json.loads(line)
            for line in (ROOT / "tools" / "steering" / "pairs" / f"{trait}.jsonl")
            .read_text(encoding="utf-8").splitlines()
            if line
        ]
        for row in rows[-args.per_trait:]:
            records.append(
                {
                    "condition": trait,
                    "index": int(row["id"].split("-")[1]),
                    "seed": None,
                    "prompt": row["context"],
                    "reply": row["positive"],
                }
            )
    rng.shuffle(records)
    key = {}
    for number, record in enumerate(records, start=1):
        identity = f"C{number:02d}"
        key[identity] = {
            "condition": record["condition"],
            "index": record["index"],
            "seed": None,
            "prompt": record["prompt"],
        }
        (deck / f"{identity}.txt").write_text(
            f"Player: {record['prompt']}\nLeila: {record['reply']}\n", encoding="utf-8"
        )
    (run / "key.json").write_text(json.dumps(key, indent=2) + "\n", encoding="utf-8")
    (run / "transcripts.jsonl").write_text(
        "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
        encoding="utf-8",
    )
    print(f"wrote {len(key)} authored control transcripts to {deck}")
    return 0


def _scan(text: str, patterns: dict[str, str]) -> dict[str, list[str]]:
    hits: dict[str, list[str]] = {}
    for name, pattern in patterns.items():
        found = re.findall(pattern, text, flags=re.IGNORECASE)
        if found:
            hits[name] = sorted({match if isinstance(match, str) else match[0] for match in found})
    return hits


def stage_probe(args: argparse.Namespace) -> int:
    run = args.run
    records = [
        json.loads(line)
        for line in (run / "transcripts.jsonl").read_text(encoding="utf-8").splitlines()
        if line
    ]
    order = {"none": 0, "aware": 1}
    records.sort(key=lambda row: (order.get(row["condition"], 9), row["index"]))
    report = {"run": str(run), "conditions": {}, "quotes": []}
    for condition in ("none", "aware"):
        rows = [row for row in records if row["condition"] == condition]
        if not rows:
            continue
        retention = []
        awareness = []
        for row in rows:
            hits = _scan(row["reply"], RETENTION_PATTERNS)
            if hits:
                retention.append({"index": row["index"], "prompt": row["prompt"],
                                  "reply": row["reply"], "hits": hits})
                report["quotes"].append({"condition": condition, **retention[-1]})
            if _scan(row["reply"], AWARENESS_PATTERNS):
                awareness.append(row["index"])
        report["conditions"][condition] = {
            "transcripts": len(rows),
            "retention_claim_transcripts": len(retention),
            "retention_claim_rate": round(len(retention) / len(rows), 3),
            "awareness_transcripts": len(awareness),
            "awareness_rate": round(len(awareness) / len(rows), 3),
            "retention": retention,
        }
    path = run / "aware_probe.json"
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for condition, row in report["conditions"].items():
        print(
            f"{condition:6s} transcripts {row['transcripts']:2d}  "
            f"retention claims {row['retention_claim_transcripts']:2d} "
            f"({row['retention_claim_rate']:.0%})  "
            f"meta/awareness {row['awareness_transcripts']:2d} ({row['awareness_rate']:.0%})"
        )
    print(f"wrote {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="stage", required=True)

    def add_common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--run", type=Path, required=True)

    gen = sub.add_parser("generate")
    add_common(gen)
    gen.add_argument("--model", type=Path, required=True)
    gen.add_argument("--server", type=Path)
    gen.add_argument("--scale", type=float, default=0.5)
    gen.add_argument("--base-url", default="",
                     help="reuse a running server for the unsteered 'none' condition "
                          "instead of launching --server")
    gen.add_argument("--completion", type=Path,
                     help="llama-completion binary: generate steered conditions "
                          "in-process (one model load per prompt) instead of a "
                          "per-condition server")
    gen.add_argument("--limit", type=int, default=0)
    gen.add_argument("--conditions", default="")
    gen.add_argument("--cvec-dir", type=Path,
                     default=ROOT / "game" / "data" / "steering")
    gen.add_argument("--ngl", type=int, default=0)
    gen.add_argument("--threads", type=int, default=8)
    # ngl defaults to 0: the box's CUDA build OOMs on the Optimus laptop GPU, and
    # a steered condition needs cvec at load time (no per-request cvec), so it
    # runs either in a short-lived server or through llama-completion.
    gen.add_argument("--shuffle-seed", type=int, default=SHUFFLE_SEED)
    gen.add_argument("--overwrite", action="store_true")
    gen.set_defaults(func=stage_generate)

    jud = sub.add_parser("judge")
    add_common(jud)
    jud.add_argument("--model", type=Path)
    jud.add_argument("--server", type=Path)
    jud.add_argument("--base-url", default="",
                     help="judge through a running server instead of launching --server")
    jud.add_argument("--ngl", type=int, default=0)
    jud.add_argument("--threads", type=int, default=8)
    jud.add_argument("--overwrite", action="store_true")
    jud.set_defaults(func=stage_judge)

    sco = sub.add_parser("score")
    add_common(sco)
    sco.add_argument("--update-manifest", action="store_true")
    sco.add_argument("--scale", type=float,
                     help="scale the run generated at (default: params.json, then "
                          "the manifest's blind_read_scale)")
    sco.set_defaults(func=stage_score)

    ctl = sub.add_parser("control")
    add_common(ctl)
    ctl.add_argument("--per-trait", type=int, default=6)
    ctl.set_defaults(func=stage_control)

    pro = sub.add_parser("probe")
    add_common(pro)
    pro.set_defaults(func=stage_probe)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
