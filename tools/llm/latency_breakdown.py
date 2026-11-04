#!/usr/bin/env python3
"""P2.26: first-beat latency breakdown against a llama-server.

Replays the prompts a real date actually sent (the transcript logger stores
every request: `prompt`, `schema` and the server's own `timings`) and measures,
per turn, where the time before the first usable `say` goes:

    POST --queue/HTTP--> prefill (prompt tokens) --> first token
         --> pre-say decode (read/inner/music/fx/beat head) --> first `say` char
         --> safety holdback (16 chars) --> first char the screen may show

It also tokenizes the emitted pre-say prefix with the server's own tokenizer
(`/tokenize`) so the pre-say cost is attributed in tokens, not guesses.

Usage (the numbers in production/handoffs/P2.26.md were produced with these):

    # faithful replay of the CPU-host playtest session, GPU server
    python3 tools/llm/latency_breakdown.py --session 1 --turns 0:6 \
        --url http://127.0.0.1:8089 --label gpu-baseline \
        --out /tmp/p226_gpu.json

    # same prompts against a CPU-only server (-ngl 0)
    python3 tools/llm/latency_breakdown.py --session 1 --turns 0:6 \
        --url http://127.0.0.1:8090 --label cpu-baseline \
        --out /tmp/p226_cpu.json

    # projection: schema order with `beats` first (measurement only, not a
    # shipped change -- this is the evidence behind the DCR in the handoff)
    python3 tools/llm/latency_breakdown.py --session 1 --turns 0:6 \
        --url http://127.0.0.1:8089 --order beats_first --system-order \
        --label gpu-beats-first --out /tmp/p226_gpu_bf.json

No third-party dependencies: urllib only.
"""

import argparse
import glob
import json
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.request

DEFAULT_TRANSCRIPT_DIR = "production/playtests/P1/transcripts"
DEFAULT_SAMPLING = {"temperature": 0.75, "top_p": 0.9, "repeat_penalty": 1.1}
MAX_TOKENS = 600
# Safety's holdback: chars of scanned `say` text the filter keeps back before
# anything may reach the screen. `_holdback = max(_MIN_HOLDBACK, _max_phrase+1)`
# (game/autoload/Safety.gd:12,289) and `_max_phrase` is the longest phrase after
# `SafetyText.normalize` — which folds homoglyphs and lowercases but KEEPS spaces.
# The longest row in game/data/safety/filter_lists.json is "i want to sleep and
# never wake up" (33) -> 34. tools/test.sh prints the same number.
DEFAULT_HOLDBACK = 34

# The grammar allows whitespace around `:` (the model sometimes emits `"say": "`),
# so the landmark has to tolerate it or a turn silently loses its first-say time.
SAY_KEY = re.compile(r'"say"\s*:\s*"')

# docs/02 §3 order, which is what Director.gd:378 sends on the wire. This has
# to be spelled out here: the transcript's copy of the schema was written
# through JSON.stringify's default `sort_keys=true`, so it is alphabetical and
# cannot be replayed as-is.
ORDER_PATCH = {
    "docs": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action", "meta"],
    "beats_first": ["beats", "read", "inner", "music", "fx", "mood", "memory", "action"],
    "say_first": ["beats", "read", "inner", "music", "fx", "mood", "memory", "action"],
    # keeps every docs/02 §1 timing property: music/fx still land before the
    # first beat's text, only the two text fields (`read`, `inner`) move after it
    "music_fx_beats_first": ["music", "fx", "beats", "read", "inner", "mood", "memory", "action"],
    # control run: the transcript's own (sorted) copy, i.e. `action` first. It
    # proves the wire schema order -- not the prompt's ordering sentence --
    # decides what the model emits, which is what DCR-1 in the handoff rests on.
    "alphabetical": ["action", "beats", "fx", "inner", "memory", "mood", "music", "read"],
}
# docs/02 §1 beat object order; the transcript copy is alphabetical (cue first),
# so a faithful replay has to restore it too.
BEAT_ORDER_DOCS = ["feeling", "intensity", "cue", "say"]
BEAT_ORDER_SAY_FIRST = ["say", "feeling", "intensity", "cue"]

SYSTEM_ORDER_SENTENCE = (
    "Respond ONLY with JSON in this exact order:\n"
    "the object's keys in exactly this sequence: {order}.\n"
)


def log(message):
    print(message, flush=True)


def first_say_span(text):
    """(start, end) of the first `"say":"` key, or (-1, -1) when it has not landed."""
    match = SAY_KEY.search(text)
    if match is None:
        return (-1, -1)
    return (match.start(), match.end())


# ---------------------------------------------------------------- transcripts


def load_records(path):
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            if "output" in record and record.get("prompt"):
                records.append(record)
    return records


def session_path(session, directory):
    matches = sorted(glob.glob(os.path.join(directory, "session_%d" % session, "*.jsonl")))
    if not matches:
        raise SystemExit("no transcript for session %d under %s" % (session, directory))
    return matches[0]


# ------------------------------------------------------------------- variants


def reorder_schema(schema, order_name):
    """Return a copy of `schema` with the object keys in another order.

    Only used by the measurement variants: the shipping schema keeps the
    docs/02 §3 property order.
    """
    if not order_name:
        return schema
    order = ORDER_PATCH[order_name]
    out = dict(schema)
    props = schema.get("properties", {})
    out["properties"] = {key: props[key] for key in order if key in props}
    for key, value in props.items():
        if key not in out["properties"]:
            out["properties"][key] = value
    if order_name == "alphabetical":
        beat_order = ["cue", "feeling", "intensity", "say"]
    elif order_name == "say_first":
        beat_order = BEAT_ORDER_SAY_FIRST
    else:
        beat_order = BEAT_ORDER_DOCS
    beats = json.loads(json.dumps(out["properties"]["beats"]))
    item = beats.get("items", {})
    item_props = item.get("properties", {})
    item["properties"] = {k: item_props[k] for k in beat_order if k in item_props}
    for key, value in item_props.items():
        if key not in item["properties"]:
            item["properties"][key] = value
    item["required"] = [k for k in beat_order if k in item.get("required", [])] + [
        k for k in item.get("required", []) if k not in beat_order
    ]
    beats["items"] = item
    out["properties"]["beats"] = beats
    required = schema.get("required", [])
    out["required"] = [k for k in order if k in required] + [k for k in required if k not in order]
    return out


def patch_system_order(messages, order_name):
    """Point the ordering instruction at the variant order (measurement only)."""
    order = ", ".join(ORDER_PATCH[order_name])
    sentence = "Respond ONLY with JSON in this exact order:\n"
    replacement = (
        "Respond ONLY with JSON in this exact order.\n"
        "The top-level keys must appear in exactly this sequence: %s.\n" % order
    )
    if order_name == "say_first":
        replacement += "Inside a beat the keys are: say, feeling, intensity, cue.\n"
    out = []
    for message in messages:
        message = dict(message)
        content = str(message.get("content", ""))
        if message.get("role") == "system" and sentence in content:
            content = content.replace(sentence, replacement)
        message["content"] = content
        out.append(message)
    return out


# ------------------------------------------------------------------ transport


def tokenize(url, text):
    if not text:
        return 0
    body = json.dumps({"content": text}).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return len(json.load(response).get("tokens", []))


def run_turn(base_url, messages, schema, sampling, cache_prompt, holdback):
    """Stream one turn and timestamp every landmark on one clock."""
    body = {
        "messages": messages,
        "stream": True,
        "max_tokens": MAX_TOKENS,
        "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": schema}},
        "chat_template_kwargs": {"enable_thinking": False},
        "cache_prompt": cache_prompt,
    }
    body.update(sampling)
    request = urllib.request.Request(
        base_url.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    started = time.perf_counter()
    landmark = {"first_byte_ms": -1, "first_token_ms": -1, "first_say_ms": -1}
    text = ""
    say_curve = []  # [chars of say text so far, ms] per chunk, for any holdback
    say_closed_ms = -1
    timings = {}
    chunks = 0
    try:
        response = urllib.request.urlopen(request, timeout=300)
    except urllib.error.HTTPError as error:
        return {"ok": False, "error": "http_%d" % error.code, "detail": error.read()[:400].decode("utf-8", "replace")}
    if landmark["first_byte_ms"] < 0:
        landmark["first_byte_ms"] = int((time.perf_counter() - started) * 1000)
    while True:
        line = response.readline()
        if not line:
            break
        if landmark["first_byte_ms"] < 0:
            landmark["first_byte_ms"] = int((time.perf_counter() - started) * 1000)
        line = line.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if payload == "[DONE]":
            break
        try:
            chunk = json.loads(payload)
        except ValueError:
            continue
        if chunk.get("timings"):
            timings = chunk["timings"]
        choices = chunk.get("choices") or []
        if not choices:
            continue
        delta = choices[0].get("delta") or {}
        piece = delta.get("content")
        if piece:
            chunks += 1
            if landmark["first_token_ms"] < 0:
                landmark["first_token_ms"] = int((time.perf_counter() - started) * 1000)
            text += piece
            say_at, body_at = first_say_span(text)
            if say_at >= 0:
                if landmark["first_say_ms"] < 0 and len(text) > body_at:
                    landmark["first_say_ms"] = int((time.perf_counter() - started) * 1000)
                closed = text.find('"', body_at)
                say_chars = (closed if closed >= 0 else len(text)) - body_at
                now_ms = int((time.perf_counter() - started) * 1000)
                say_curve.append([say_chars, now_ms])
                if closed >= 0 and say_closed_ms < 0:
                    # A beat shorter than the holdback is released in one go at
                    # its closing quote (`Safety.end_say`), so that is the first
                    # moment the screen can show it.
                    say_closed_ms = now_ms
    total_ms = int((time.perf_counter() - started) * 1000)
    response.close()
    visible_ms = -1
    visible_chars = 0
    for chars, at_ms in say_curve:
        if chars >= holdback:
            visible_ms, visible_chars = at_ms, chars
            break
    if visible_ms < 0 and say_closed_ms >= 0:
        visible_ms = say_closed_ms
        visible_chars = say_curve[-1][0] if say_curve else 0
    _, body_at = first_say_span(text)
    pre_say_text = text[:body_at] if body_at > 0 else ""
    return {
        "ok": bool(text),
        "text": text,
        "chunks": chunks,
        "pre_say_text": pre_say_text,
        "timings": timings,
        "first_byte_ms": landmark["first_byte_ms"],
        "first_token_ms": landmark["first_token_ms"],
        "first_say_ms": landmark["first_say_ms"],
        "visible_ms": visible_ms,
        "visible_chars": visible_chars,
        "say_curve": say_curve,
        "total_ms": total_ms,
    }


# ------------------------------------------------------------------- reporting


def summarise(rows):
    def stats(key):
        values = [row[key] for row in rows if isinstance(row.get(key), (int, float)) and row[key] >= 0]
        if not values:
            return None
        ordered = sorted(values)
        return {
            "n": len(values),
            "min": ordered[0],
            "median": statistics.median(ordered),
            "p95": ordered[max(0, int(round(0.95 * len(ordered))) - 1)],
            "max": ordered[-1],
        }

    keys = [
        "first_byte_ms",
        "first_token_ms",
        "first_say_ms",
        "visible_ms",
        "total_ms",
        "pre_say_tokens",
        "prompt_n",
        "cache_n",
        "prompt_ms",
        "predicted_n",
        "predicted_per_second",
        "pre_say_ms",
        "pre_say_ms_per_token",
        "holdback_ms",
    ]
    return {key: stats(key) for key in keys}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", default="http://127.0.0.1:8089")
    parser.add_argument("--session", type=int, default=1)
    parser.add_argument("--transcript", default="")
    parser.add_argument("--transcript-dir", default=DEFAULT_TRANSCRIPT_DIR)
    parser.add_argument("--turns", default="0:4", help="first:last (exclusive) turn slice")
    parser.add_argument("--order", default="docs", choices=sorted(ORDER_PATCH))
    parser.add_argument("--system-order", action="store_true", help="patch the ordering sentence too")
    parser.add_argument("--no-cache", action="store_true", help="cache_prompt=false (cold KV per turn)")
    parser.add_argument("--holdback", type=int, default=DEFAULT_HOLDBACK)
    parser.add_argument("--label", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)

    path = args.transcript or session_path(args.session, args.transcript_dir)
    records = load_records(path)
    first, _, last = args.turns.partition(":")
    first = int(first or 0)
    last = int(last) if last else len(records)
    records = records[first:last]
    label = args.label or "%s_%s" % (os.path.basename(path), args.order)

    log("# latency breakdown — %s" % label)
    log("# transcript: %s (turns %d..%d, %d records)" % (path, first, last - 1, len(records)))
    log("# server: %s  order=%s  system_order=%s  cache=%s"
        % (args.url, args.order, args.system_order, not args.no_cache))
    log("")
    log("%3s %7s %7s %7s %7s %7s %6s %6s %7s %8s %6s %7s"
        % ("turn", "byte", "1st_tok", "1st_say", "visible", "total", "p_tok", "pre_say", "prefill", "pre_ms/t", "p_n", "c_n"))
    rows = []
    for index, record in enumerate(records):
        messages = record["prompt"]
        if args.order != "docs" and args.system_order:
            messages = patch_system_order(messages, args.order)
        schema = reorder_schema(record["schema"], args.order)
        sampling = dict(DEFAULT_SAMPLING)
        if record.get("stage") is not None:
            try:
                table = json.load(open("game/data/sampling.json", "r", encoding="utf-8"))
                row = table["stages"].get(str(record["stage"]))
                if isinstance(row, dict):
                    for key in ("temperature", "top_p", "repeat_penalty"):
                        if key in row:
                            sampling[key] = row[key]
            except (OSError, ValueError, KeyError):
                pass
        result = run_turn(args.url, messages, schema, sampling, not args.no_cache, args.holdback)
        if not result.get("ok"):
            log("%3d  FAILED %s %s" % (index, result.get("error"), result.get("detail", "")[:160]))
            rows.append({"turn": index, "ok": False, "error": result.get("error")})
            continue
        timings = result["timings"] or {}
        pre_say_tokens = tokenize(args.url + "/tokenize", result["pre_say_text"])
        first_token = result["first_token_ms"]
        first_say = result["first_say_ms"]
        pre_say_ms = (first_say - first_token) if first_say >= 0 and first_token >= 0 else -1
        row = {
            "turn": index,
            "ok": True,
            "first_byte_ms": result["first_byte_ms"],
            "first_token_ms": first_token,
            "first_say_ms": first_say,
            "visible_ms": result["visible_ms"],
            "total_ms": result["total_ms"],
            "pre_say_tokens": pre_say_tokens,
            "pre_say_ms": pre_say_ms,
            "pre_say_ms_per_token": round(pre_say_ms / pre_say_tokens, 2) if pre_say_tokens > 0 and pre_say_ms > 0 else -1,
            "holdback_ms": (result["visible_ms"] - first_say) if result["visible_ms"] >= 0 and first_say >= 0 else -1,
            "visible_chars": result["visible_chars"],
            "say_curve": result["say_curve"],
            "prompt_n": timings.get("prompt_n", -1),
            "cache_n": timings.get("cache_n", -1),
            "prompt_ms": timings.get("prompt_ms", -1),
            "predicted_n": timings.get("predicted_n", -1),
            "predicted_ms": timings.get("predicted_ms", -1),
            "predicted_per_second": timings.get("predicted_per_second", -1),
            "chunks": result["chunks"],
            "output": result["text"],
            "pre_say_text": result["pre_say_text"],
        }
        rows.append(row)
        log("%3d %7d %7d %7s %7s %7d %6d %7d %7d %8s %6s %6s"
            % (index, row["first_byte_ms"], row["first_token_ms"],
               row["first_say_ms"] if row["first_say_ms"] >= 0 else "-",
               row["visible_ms"] if row["visible_ms"] >= 0 else "-",
               row["total_ms"], row["pre_say_tokens"], row["pre_say_ms"],
               int(row["prompt_ms"]) if row["prompt_ms"] >= 0 else -1,
               row["pre_say_ms_per_token"], int(row["prompt_n"]), int(row["cache_n"])))

    summary = summarise([row for row in rows if row.get("ok")])
    log("")
    for key, stat in summary.items():
        if stat:
            log("%-22s n=%-3d min=%-7.1f median=%-7.1f p95=%-7.1f max=%-7.1f"
                % (key, stat["n"], stat["min"], stat["median"], stat["p95"], stat["max"]))

    payload = {"label": label, "url": args.url, "order": args.order, "transcript": path,
               "turns": [first, last], "holdback": args.holdback, "rows": rows, "summary": summary}
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=1)
        log("\nwrote %s" % args.out)
    return 0 if all(row.get("ok") for row in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
