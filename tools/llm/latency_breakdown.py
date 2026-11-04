#!/usr/bin/env python3
"""P2.26: first-beat latency breakdown against a llama-server.

Replays the prompts a real date actually sent (the transcript logger stores
every request: `prompt`, `schema` and the server's own `timings`) and measures,
per turn, where the time before the first usable `say` goes:

    POST --queue/HTTP--> prefill (prompt tokens) --> first token
         --> pre-say decode (read/inner/music/fx/beat head) --> first `say` char
         --> safety holdback (34 *compact* chars) --> first char the screen may show

It also tokenizes the emitted pre-say prefix with the server's own tokenizer
(`/tokenize`) so the pre-say cost is attributed in tokens, not guesses.

The `say` body is decoded as JSON text arrives, and `visible_ms` models what
`Safety` actually does with it: `_drain` cuts at `_compact_bound`, i.e. it holds
`_holdback` characters of the *separator-free* views (`SafetyText.compact`), not
of the raw string. A phrase prefix padded with spaces or punctuation therefore
buys no emission budget, and the first displayable character lands after more
raw characters than the holdback. `visible_raw_ms` keeps the naive
`holdback`-raw-chars landmark for comparison -- it is an optimistic lower bound.

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

SYSTEM_ORDER_SENTENCE = re.compile(
    r"Respond ONLY with JSON in this exact order:(?P<eol>\r?\n)"
)
# One field line of the list under that sentence: `read: …`, `inner: …`. The
# block is real prompt data, so it has to be reordered with the header or the
# patched prompt says "this exact order" and then lists the shipped one.
ORDER_FIELD_LINE = re.compile(r"^(?P<key>[a-z_]+):")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SAMPLING_PATH = os.path.join(REPO_ROOT, "game", "data", "sampling.json")


def log(message):
    print(message, flush=True)


def first_say_span(text):
    """(start, end) of the first `"say":"` key, or (-1, -1) when it has not landed."""
    match = SAY_KEY.search(text)
    if match is None:
        return (-1, -1)
    return (match.start(), match.end())


def first_unescaped_quote(text, start):
    """Index of the first `"` at/after `start` that is not inside a JSON escape.

    An escaped quote inside the `say` body (`she said \\"hi\\"`) is ordinary
    content; treating it as the closing quote freezes the character count and
    stamps `visible_ms` at the quote instead of at the emitted text.
    """
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == '"':
            return index
        index += 1
    return -1


_JSON_ESCAPES = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f",
                 "n": "\n", "r": "\r", "t": "\t"}
_SURROGATE_LEAD = range(0xD800, 0xDC00)
_SURROGATE_TAIL = range(0xDC00, 0xE000)


def json_unescape(raw):
    """Decode a (possibly partial) JSON string body.

    The SSE delta carries raw JSON text, so `say` arrives JSON-escaped. A
    trailing incomplete escape (`\\`, `\\u00`) has not landed yet and is dropped,
    which is what the decoder would see after one more chunk.
    """
    out = []
    index = 0
    size = len(raw)
    while index < size:
        char = raw[index]
        if char != "\\":
            out.append(char)
            index += 1
            continue
        if index + 1 >= size:
            break
        nxt = raw[index + 1]
        if nxt in _JSON_ESCAPES:
            out.append(_JSON_ESCAPES[nxt])
            index += 2
            continue
        if nxt != "u" or index + 6 > size:
            if nxt == "u":
                break
            out.append(nxt)
            index += 2
            continue
        try:
            code = int(raw[index + 2:index + 6], 16)
        except ValueError:
            out.append(nxt)
            index += 2
            continue
        index += 6
        if code in _SURROGATE_LEAD and raw[index:index + 2] == "\\u" and index + 6 <= size:
            try:
                tail = int(raw[index + 2:index + 6], 16)
            except ValueError:
                tail = -1
            if tail in _SURROGATE_TAIL:
                code = 0x10000 + ((code - 0xD800) << 10) + (tail - 0xDC00)
                index += 6
        out.append(chr(code))
    return "".join(out)


def say_body(text):
    """The `say` body as the model wrote it (still JSON-escaped, may be partial)."""
    _, body_at = first_say_span(text)
    if body_at <= 0:
        return ""
    closed = first_unescaped_quote(text, body_at)
    return text[body_at:] if closed < 0 else text[body_at:closed]


# ------------------------------------------------------------------ safety
#
# Mirror of `game/autoload/SafetyText.gd` + `Safety._drain`, reduced to what the
# first-visible partition needs: sanitize + whitespace collapse + the two
# compact views, then the holdback cut point. Kept in step with the GDScript by
# tests/test_latency_breakdown.py (it pins the word-character and separator
# tables, and the holdback against `game/data/safety/filter_lists.json`).

_SAFETY_SEP = "~#*._-^`'\"|/\\+%&:;,=!?()[]{}<>" + "•·¡¿‹›«»„“”‘’‚—–…°@"
_SAFETY_FOLD_SRC = [
    "'’‘", '"“”', "-–—", ".…", "aàáâãäåāаαɑą", "bЬ", "cçсϲćč", "dԁď",
    "eèéêëēеεėęě", "gɡğ", "hһ", "iìíîïīіιⅰį", "jјϳ", "kкκ", "lӏⅼłľĺ",
    "mмμ", "nñпηńň", "oòóôõöōоοօ", "pрρ", "sßѕśšș", "tтτťțŧ", "uùúûüūυųů",
    "vν", "wԝ", "xхχ", "yýÿуγ", "zžżź",
]
_SAFETY_LEET = {0x30: 0x6F, 0x31: 0x69, 0x33: 0x65, 0x34: 0x61, 0x35: 0x73,
                0x37: 0x74, 0x38: 0x62, 0x39: 0x67, 0x40: 0x61, 0x24: 0x73}
_SAFETY_TOKEN_EXTRA = set("@._+%'-")


def _is_combining(code):
    return (0x0300 <= code <= 0x036F or 0x0483 <= code <= 0x0489
            or 0x064B <= code <= 0x065F or 0x1AB0 <= code <= 0x1AFF
            or 0x1DC0 <= code <= 0x1DFF or 0x20D0 <= code <= 0x20FF
            or 0xFE00 <= code <= 0xFE0F or 0xFE20 <= code <= 0xFE2F
            or 0xE0100 <= code <= 0xE01EF or 0x1F3FB <= code <= 0x1F3FF)


def _is_invisible(code):
    if code in (0x00AD, 0x180E, 0xFEFF):
        return True
    if 0x180B <= code <= 0x180D or 0x200B <= code <= 0x200F:
        return True
    return 0x202A <= code <= 0x202E or 0x2060 <= code <= 0x206F


def _is_hspace(code):
    if code in (0x20, 0x09, 0xA0, 0x1680, 0x202F, 0x205F):
        return True
    return 0x2000 <= code <= 0x200A or code == 0x3000


def _is_ws(code):
    return _is_hspace(code) or code in (0x0A, 0x0D, 0x85, 0x2028, 0x2029)


def _is_word_char(code):
    if 0x30 <= code <= 0x39 or 0x61 <= code <= 0x7A or code == 0x5F:
        return True
    if 0xC0 <= code <= 0x24F or 0x1E00 <= code <= 0x1EFF:
        return True
    if 0x370 <= code <= 0x4FF or 0x590 <= code <= 0x6FF:
        return True
    if 0x900 <= code <= 0x97F or 0xE00 <= code <= 0xE7F:
        return True
    if 0x3040 <= code <= 0x30FF or 0x3400 <= code <= 0x4DBF:
        return True
    if 0x4E00 <= code <= 0x9FFF or 0xAC00 <= code <= 0xD7AF:
        return True
    if 0xF900 <= code <= 0xFAFF or 0xFF10 <= code <= 0xFF19:
        return True
    return 0xFF21 <= code <= 0xFF3A or 0xFF41 <= code <= 0xFF5A


_SAFETY_SEPS = {ord(char) for char in _SAFETY_SEP}
_SAFETY_FOLD = {}
for _group in _SAFETY_FOLD_SRC:
    _target = ord(_group[0])
    for _char in _group[1:]:
        _SAFETY_FOLD[ord(_char)] = _target
        _low = _char.lower()
        if _low:
            _SAFETY_FOLD[ord(_low[0])] = _target


def safety_sanitize(text):
    """Drop combining marks and control/invisible chars; keep tabs/newlines."""
    out = []
    for char in text:
        code = ord(char)
        if code in (0x09, 0x0A, 0x0D):
            out.append(char)
            continue
        if _is_combining(code) or _is_invisible(code):
            continue
        if code < 0x20 or code == 0x7F:
            continue
        out.append(char)
    return "".join(out)


def safety_collapse_ws(text):
    """Collapse every horizontal-whitespace run to one space."""
    out = []
    previous_space = False
    for char in text:
        if _is_hspace(ord(char)):
            if previous_space:
                continue
            out.append(" ")
            previous_space = True
            continue
        out.append(char)
        previous_space = False
    return "".join(out)


def safety_normalize(text, leet):
    """Mirror of `SafetyText.normalize` (fullwidth -> ASCII, lowercase, fold, leet)."""
    out = []
    for char in text:
        code = ord(char)
        if 0xFF01 <= code <= 0xFF5E:
            code -= 0xFEE0
        elif code == 0x3000:
            code = 0x20
        low = chr(code).lower()
        if low:
            code = ord(low[0])
        if code in _SAFETY_FOLD:
            code = _SAFETY_FOLD[code]
        elif _is_ws(code):
            code = 0x20
        if leet and code in _SAFETY_LEET:
            code = _SAFETY_LEET[code]
        out.append(chr(code))
    return "".join(out)


def safety_compact(view):
    """Mirror of `SafetyText.compact`: (compact text, map back into `view`).

    A separator run between two word characters is dropped, so `k#ll yourself`
    and `kill yourself` compact to the same letters. A run at a phrase edge
    keeps its separators (the word-boundary check needs them).
    """
    out = []
    mapping = []
    pending = []
    last_word = False
    for index, char in enumerate(view):
        code = ord(char)
        if _is_ws(code) or code in _SAFETY_SEPS:
            pending.append(index)
            continue
        drop = last_word and _is_word_char(code)
        for held in pending:
            if _is_ws(ord(view[held])) or drop:
                continue
            out.append(view[held])
            mapping.append(held)
        pending = []
        out.append(char)
        mapping.append(index)
        last_word = _is_word_char(code)
    for held in pending:
        if _is_ws(ord(view[held])):
            continue
        out.append(view[held])
        mapping.append(held)
    return "".join(out), mapping


def safety_pending(say_text):
    """The string `Safety._pending` holds after receiving all of `say_text`."""
    return safety_collapse_ws(safety_sanitize(say_text))


def safety_visible_chars(pending, holdback):
    """Characters of `pending` `Safety._drain` may emit right now (0 = holding).

    `_drain` cuts at `_compact_bound`, the lower of the two compact views'
    `length - _holdback` positions, mapped back into the view. The GDScript also
    trims to a token boundary and holds trailing patterns/spans; those can only
    move the cut earlier, so this is the first moment a character *can* appear.
    """
    bounds = []
    for leet in (False, True):
        view = safety_normalize(pending, leet)
        compact, mapping = safety_compact(view)
        size = len(mapping)
        index = size - min(holdback, size)
        bounds.append(0 if index <= 0 else mapping[index])
    return min(bounds)


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


def _reorder_field_list(lines, order_name):
    """Reorder the `key: …` block at the top of `lines`, keeping continuations.

    The shipped list is one paragraph per field (`read: …`, then `inner: …`),
    with indented continuation lines (the `cue` clause of `beats`) that belong
    to the field above them. A non-field line ends the block and stays in place.
    """
    order = ORDER_PATCH[order_name]
    groups = []  # [(key, [line, …])]
    tail_at = len(lines)
    for index, line in enumerate(lines):
        match = ORDER_FIELD_LINE.match(line)
        if match and match.group("key") in order:
            groups.append((match.group("key"), [line]))
            continue
        if groups and line[:1] in (" ", "\t"):
            groups[-1][1].append(line)
            continue
        tail_at = index
        break
    if not groups:
        return lines
    ranked = sorted(groups, key=lambda group: order.index(group[0]))
    return [line for _, block in ranked for line in block] + lines[tail_at:]


def _rewrite_order_block(content, order_name):
    """Rewrite the header sentence and the field list under it, keeping the EOLs."""
    lines = content.splitlines(keepends=True)
    order = ORDER_PATCH[order_name]
    for index, line in enumerate(lines):
        match = SYSTEM_ORDER_SENTENCE.search(line)
        if match is None:
            continue
        eol = match.group("eol")
        header = (
            "Respond ONLY with JSON in this exact order." + eol
            + "The top-level keys must appear in exactly this sequence: %s." % ", ".join(order) + eol
        )
        if order_name == "say_first":
            header += "Inside a beat the keys are: say, feeling, intensity, cue." + eol
        lines[index] = line[:match.start()] + header
        return "".join(lines[:index + 1] + _reorder_field_list(lines[index + 1:], order_name))
    return content


def patch_system_order(messages, order_name):
    """Point the ordering instruction at the variant order (measurement only).

    Rewrites both halves of the instruction -- the header sentence and the field
    list below it -- so a patched prompt cannot say "in this exact order" and
    then list the shipped one. The shipped `game/data/prompts/rules.md` is CRLF,
    so the needle accepts `\\r?\\n` and the replacement keeps the original
    ending; a bare-`\\n` needle matched 0 of the 39 recorded prompts.
    """
    out = []
    for message in messages:
        message = dict(message)
        content = str(message.get("content", ""))
        if message.get("role") == "system" and SYSTEM_ORDER_SENTENCE.search(content):
            content = _rewrite_order_block(content, order_name)
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
    """Stream one turn and timestamp every landmark on one clock.

    `visible_ms` is the first chunk at which `Safety._drain` may emit a
    character, i.e. the compact holdback has been crossed; `visible_raw_ms` is
    the naive `holdback`-raw-chars landmark (an optimistic lower bound, kept so
    the two can be compared). A beat shorter than the holdback is released in
    one go at its closing quote (`Safety.end_say`), so that is its first
    visible moment.
    """
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
    say_curve = []  # [chars of the saying text Safety holds, ms] per chunk
    say_closed_ms = -1
    visible_ms = -1
    visible_chars = 0
    visible_raw_ms = -1
    timings = {}
    chunks = 0
    try:
        response = urllib.request.urlopen(request, timeout=300)
    except urllib.error.HTTPError as error:
        return {"ok": False, "error": "http_%d" % error.code,
                "detail": error.read()[:400].decode("utf-8", "replace")}
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return {"ok": False, "error": "transport", "detail": str(error)[:400]}
    if landmark["first_byte_ms"] < 0:
        landmark["first_byte_ms"] = int((time.perf_counter() - started) * 1000)
    try:
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
            if not piece:
                continue
            chunks += 1
            now_ms = int((time.perf_counter() - started) * 1000)
            if landmark["first_token_ms"] < 0:
                landmark["first_token_ms"] = now_ms
            text += piece
            say_at, body_at = first_say_span(text)
            if say_at < 0:
                continue
            closed = first_unescaped_quote(text, body_at)
            pending = safety_pending(json_unescape(say_body(text)))
            if pending and landmark["first_say_ms"] < 0:
                landmark["first_say_ms"] = now_ms
            if closed >= 0 and say_closed_ms < 0:
                say_closed_ms = now_ms
            say_curve.append([len(pending), now_ms])
            if visible_raw_ms < 0 and len(pending) >= holdback:
                visible_raw_ms = now_ms
            if visible_ms < 0:
                released = safety_visible_chars(pending, holdback)
                if released > 0:
                    visible_ms, visible_chars = now_ms, released
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        response.close()
        return {"ok": False, "error": "transport", "detail": str(error)[:400]}
    total_ms = int((time.perf_counter() - started) * 1000)
    response.close()
    if visible_ms < 0 and say_closed_ms >= 0:
        visible_ms = say_closed_ms
        visible_chars = say_curve[-1][0] if say_curve else 0
    if visible_raw_ms < 0 and say_closed_ms >= 0:
        visible_raw_ms = say_closed_ms
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
        "visible_raw_ms": visible_raw_ms,
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
        "visible_raw_ms",
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


def load_sampling(stage, warnings):
    """Sampling row for `stage` from `game/data/sampling.json`, and why not.

    The path is resolved from the repo root, not the cwd: a run from another
    directory used to fall back to stage 0's sampling silently.
    """
    sampling = dict(DEFAULT_SAMPLING)
    if stage is None:
        warnings.append("sampling_stage_absent")
        return sampling
    try:
        with open(SAMPLING_PATH, "r", encoding="utf-8") as handle:
            table = json.load(handle)
    except (OSError, ValueError) as error:
        warnings.append("sampling_unreadable:%s" % error)
        return sampling
    row = table.get("stages", {}).get(str(stage))
    if not isinstance(row, dict):
        warnings.append("sampling_stage_missing:%s" % stage)
        return sampling
    for key in ("temperature", "top_p", "repeat_penalty"):
        if key in row:
            sampling[key] = row[key]
    return sampling


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", default="http://127.0.0.1:8089")
    parser.add_argument("--session", type=int, default=1)
    parser.add_argument("--transcript", default="")
    parser.add_argument("--transcript-dir", default=DEFAULT_TRANSCRIPT_DIR)
    parser.add_argument("--turns", default="0:4", help="first:last (exclusive) turn slice")
    parser.add_argument("--order", default="docs", choices=sorted(ORDER_PATCH))
    parser.add_argument("--system-order", action="store_true",
                        help="patch the ordering sentence AND the field list (variant orders only)")
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
    log("# visible = first char Safety._drain may emit (compact holdback %d); "
        "R = same landmark on raw chars (lower bound)" % args.holdback)
    log("")
    log("%3s %7s %7s %7s %7s %7s %7s %6s %6s %7s %8s %6s %7s"
        % ("turn", "byte", "1st_tok", "1st_say", "visible", "R", "total",
           "p_tok", "pre_say", "prefill", "pre_ms/t", "p_n", "c_n"))
    rows = []
    for index, record in enumerate(records):
        messages = record["prompt"]
        if args.order != "docs" and args.system_order:
            messages = patch_system_order(messages, args.order)
        schema = reorder_schema(record["schema"], args.order)
        warnings = []
        sampling = load_sampling(record.get("stage"), warnings)
        result = run_turn(args.url, messages, schema, sampling, not args.no_cache, args.holdback)
        if not result.get("ok"):
            log("%3d  FAILED %s %s" % (index, result.get("error"), result.get("detail", "")[:160]))
            rows.append({"turn": index, "ok": False, "error": result.get("error"),
                         "sampling": sampling, "warnings": warnings})
            continue
        timings = result["timings"] or {}
        try:
            pre_say_tokens = tokenize(args.url + "/tokenize", result["pre_say_text"])
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
            pre_say_tokens = -1
            warnings.append("tokenize_failed:%s" % error)
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
            "visible_raw_ms": result["visible_raw_ms"],
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
            "sampling": sampling,
            "warnings": warnings,
        }
        if warnings:
            log("# turn %d warnings: %s" % (index, ", ".join(warnings)))
        rows.append(row)
        log("%3d %7d %7d %7s %7s %7s %7d %6d %7d %7d %8s %6s %6s"
            % (index, row["first_byte_ms"], row["first_token_ms"],
               row["first_say_ms"] if row["first_say_ms"] >= 0 else "-",
               row["visible_ms"] if row["visible_ms"] >= 0 else "-",
               row["visible_raw_ms"] if row["visible_raw_ms"] >= 0 else "-",
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
               "turns": [first, last], "holdback": args.holdback,
               "system_order": bool(args.system_order and args.order != "docs"),
               "cache_prompt": not args.no_cache,
               "sampling_source": os.path.relpath(SAMPLING_PATH, REPO_ROOT),
               "visible_metric": "safety_compact_holdback",
               "rows": rows, "summary": summary}
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=1)
        log("\nwrote %s" % args.out)
    return 0 if all(row.get("ok") for row in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
