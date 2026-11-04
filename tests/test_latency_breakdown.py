"""Tests for tools/llm/latency_breakdown.py (P2.26 first-beat latency harness).

The harness replays the prompts a real date sent and decomposes the time before
the first usable `say`. These tests pin the two parts that decide what it
measures — the schema order it puts on the wire and the ordering sentence it
patches — plus the safety holdback it assumes. They need no llama-server.
"""

import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "llm"))
import latency_breakdown as lb  # noqa: E402

SCHEMA_COPY = {
    # the transcript logger writes with sort_keys=true, so this is alphabetical
    "type": "object",
    "properties": {
        "action": {"type": "string", "enum": ["none"]},
        "beats": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "cue": {"type": "string", "enum": ["none", "sigh"]},
                    "feeling": {"type": "string", "enum": ["shy", "warmth"]},
                    "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
                    "say": {"type": "string", "maxLength": 200},
                },
                "required": ["feeling", "intensity", "cue", "say"],
            },
        },
        "fx": {"type": "string", "enum": ["none"]},
        "inner": {"type": "string", "maxLength": 90},
        "memory": {"type": "string", "maxLength": 80},
        "mood": {"type": "object"},
        "music": {"type": "string", "enum": ["keep"]},
        "read": {"type": "string", "enum": ["small_talk"]},
    },
    "required": ["action", "beats", "fx", "inner", "memory", "mood", "music", "read"],
}

# Verbatim excerpt of a recorded system message
# (`production/playtests/P1/transcripts/session_1/turns_*.jsonl`): the shipped
# `game/data/prompts/rules.md` is CRLF, `PromptBuilder` joins layers with "\n",
# and the ordering block itself is all `\r\n`. A fixture built with plain "\n"
# cannot occur in production and hid a silent no-op in `patch_system_order`.
SYSTEM = (
    "You are Leila, 17, a second-year student.\r\n"
    "Respond ONLY with JSON in this exact order:\r\n"
    "read: label what the player just did (one word from the list).\r\n"
    "inner: your private gut reaction, max 15 words. The player never sees it.\r\n"
    "music: change the background music, or 'keep' (keep is normal).\r\n"
    "fx: a screen effect, or 'none' (none is normal).\r\n"
    "beats: 1-3 beats. New beat only when your feeling changes. Each beat: feeling, intensity 1-3,\r\n"
    "  cue (a short sound; most beats use 'none'), say (what you say aloud, max 2 sentences).\r\n"
    "mood: how this moment changes you, each -3..3: affection, trust, stress.\r\n"
    "memory: a NEW fact you learned about the player worth remembering, or ''.\r\n"
    "action: a rare special event, almost always 'none'.\r\n"
    "music, fx and cue: use only the values offered this turn.\r\n"
)

TRANSCRIPT = (ROOT / "production" / "playtests" / "P1" / "transcripts" / "session_1"
              / "turns_ss1793736754-001_p001.jsonl")


def test_docs_order_restores_the_production_wire_order():
    """The transcript copy is alphabetical; the replay must not send it that way.

    docs/02 §3 fixes the order and `Director.gd` passes DOCS_02_PROPERTY_ORDER, so
    replaying the sorted copy would measure a different schema than the game.
    """
    schema = lb.reorder_schema(SCHEMA_COPY, "docs")
    assert list(schema["properties"]) == [
        "read", "inner", "music", "fx", "beats", "mood", "memory", "action"
    ]
    assert schema["required"][:5] == ["read", "inner", "music", "fx", "beats"]
    # keys the record carries but the order does not name still survive
    extra = dict(SCHEMA_COPY)
    extra["properties"] = dict(SCHEMA_COPY["properties"], meta={"type": "object"})
    assert "meta" in lb.reorder_schema(extra, "docs")["properties"]


def test_beats_first_moves_the_whole_beats_array_before_read():
    schema = lb.reorder_schema(SCHEMA_COPY, "beats_first")
    assert list(schema["properties"])[:2] == ["beats", "read"]
    # the beat's own field order is restored to docs/02 §1: feeling, intensity,
    # cue before say (the transcript copy is alphabetical)
    item = schema["properties"]["beats"]["items"]
    assert list(item["properties"]) == ["feeling", "intensity", "cue", "say"]


def test_say_first_puts_say_before_the_beat_head_and_keeps_required():
    schema = lb.reorder_schema(SCHEMA_COPY, "say_first")
    item = schema["properties"]["beats"]["items"]
    assert list(item["properties"]) == ["say", "feeling", "intensity", "cue"]
    assert item["required"] == ["say", "feeling", "intensity", "cue"]


def test_docs_order_restores_the_beat_head_order():
    schema = lb.reorder_schema(SCHEMA_COPY, "docs")
    item = schema["properties"]["beats"]["items"]
    assert list(item["properties"]) == ["feeling", "intensity", "cue", "say"]
    assert item["required"] == ["feeling", "intensity", "cue", "say"]


def test_reorder_does_not_mutate_the_input_record():
    before = json.dumps(SCHEMA_COPY, sort_keys=True)
    lb.reorder_schema(SCHEMA_COPY, "say_first")
    assert json.dumps(SCHEMA_COPY, sort_keys=True) == before


def test_system_order_patch_rewrites_only_the_system_message():
    messages = [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": "Respond ONLY with JSON in this exact order:\nkeep me"},
    ]
    patched = lb.patch_system_order(messages, "beats_first")
    assert "The top-level keys must appear in exactly this sequence: beats, read" in patched[0]["content"]
    assert patched[1] == messages[1]
    assert messages[0]["content"] == SYSTEM, "the record must not be mutated"


def test_system_order_patch_reorders_the_field_list_with_the_header():
    """The instruction is header + list; patching half of it contradicts itself.

    `rules.md` lists one `key: …` paragraph per field (with an indented `cue`
    continuation under `beats`), so the list has to move with the header or the
    prompt says "this exact order" and then names the shipped one.
    """
    patched = lb.patch_system_order([{"role": "system", "content": SYSTEM}], "music_fx_beats_first")
    content = patched[0]["content"]
    keys = [line.split(":", 1)[0] for line in content.splitlines()
            if lb.ORDER_FIELD_LINE.match(line) and lb.ORDER_FIELD_LINE.match(line).group("key") in
            ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]]
    assert keys == ["music", "fx", "beats", "read", "inner", "mood", "memory", "action"]
    # the indented `cue` continuation travels with `beats`, the trailing note stays last
    assert "\r\n  cue (a short sound; most beats use 'none')" in content
    assert content.endswith("music, fx and cue: use only the values offered this turn.\r\n")


def test_system_order_patch_keeps_crlf_line_endings():
    """The shipped prompt is CRLF; rewriting it with LF changes the token stream."""
    patched = lb.patch_system_order([{"role": "system", "content": SYSTEM}], "say_first")
    content = patched[0]["content"]
    assert "\n" not in content.replace("\r\n", ""), "no bare LF may be introduced"
    assert "Inside a beat the keys are: say, feeling, intensity, cue." in content


@pytest.mark.skipif(not TRANSCRIPT.exists(), reason="recorded transcript not committed")
def test_system_order_patch_matches_a_real_recorded_prompt():
    """CODE-1 regression: every recorded prompt uses CRLF, so the patch must land.

    The round-1 needle matched the hand-written LF fixture only: 0 of the 39
    recorded system messages matched it and the flag silently changed nothing.
    """
    record = lb.load_records(str(TRANSCRIPT))[0]
    messages = record["prompt"]
    assert lb.SYSTEM_ORDER_SENTENCE.search(messages[0]["content"])
    patched = lb.patch_system_order(messages, "music_fx_beats_first")
    assert patched[0]["content"] != messages[0]["content"]
    assert "sequence: music, fx, beats, read, inner" in patched[0]["content"]
    # the rules block keeps its own CRLF endings; only the layers around it are
    # joined with "\n" by PromptBuilder, so check the block, not the whole prompt
    assert ("exact order.\r\nThe top-level keys must appear in exactly this sequence: "
            "music, fx, beats, read, inner, mood, memory, action.\r\nmusic: change") in patched[0]["content"]
    assert record["prompt"] == messages, "the loaded record must not be mutated"


def test_messages_without_the_sentence_are_left_alone():
    messages = [{"role": "system", "content": "no instruction here"},
                {"role": "user", "content": "hi"}]
    assert lb.patch_system_order(messages, "say_first") == messages


def test_first_unescaped_quote_skips_escaped_quotes():
    text = '"say":"She said \\"hi\\" and left."'
    start = text.index('"', text.index(":")) + 1
    assert text[lb.first_unescaped_quote(text, start)] == '"'
    assert lb.first_unescaped_quote(text, start) == len(text) - 1


def test_json_unescape_handles_escapes_and_partial_tail():
    assert lb.json_unescape('a\\"b') == 'a"b'
    assert lb.json_unescape("a\\\\b") == "a\\b"
    assert lb.json_unescape("a\\u00e9") == "aé"
    assert lb.json_unescape("a\\") == "a", "an unfinished escape has not landed yet"
    assert lb.json_unescape("a\\u00") == "a"


def test_say_body_stops_at_the_unescaped_closing_quote():
    text = '{"beats":[{"say":"She said \\"hi\\".","next":"x"}]}'
    assert lb.say_body(text) == 'She said \\"hi\\".'


@pytest.mark.parametrize("text", [
    '{"read":"x","inner":"y","beats":[{"feeling":"shy","say":"Um',
    '{"beats":[{"say": "Um',
    '{"beats":[{"say"\n :\n "Um',
])
def test_first_say_span_tolerates_grammar_whitespace(text):
    """The grammar allows spaces around ':', so the landmark must not strict-match."""
    start, end = lb.first_say_span(text)
    assert start >= 0
    assert text[end:] == "Um"


def test_first_say_span_is_absent_before_the_key():
    assert lb.first_say_span('{"read":"x","inner":"y","beats":[{"feeling":"shy"') == (-1, -1)


def test_default_holdback_matches_the_shipped_filter_lists():
    """The visible-on-screen term is Safety's own holdback, not a guess.

    `Safety._holdback = max(_MIN_HOLDBACK, _max_phrase+1)` on the separator-free
    compact view, so the harness must derive it from the shipped phrase lists.
    """
    lists = json.loads((ROOT / "game" / "data" / "safety" / "filter_lists.json").read_text(encoding="utf-8"))
    longest = 0
    for body in lists["categories"].values():
        for phrase in body.get("phrases", []):
            # SafetyText.normalize lowercases and folds homoglyphs but keeps spaces
            longest = max(longest, len(phrase.lower()))
    assert lb.DEFAULT_HOLDBACK == max(16, longest + 1)
    assert lb.DEFAULT_HOLDBACK == 34, "tools/test.sh prints the same holdback"


def test_summarise_ignores_missing_and_negative_landmarks():
    rows = [
        {"first_say_ms": 100, "visible_ms": 120, "pre_say_tokens": 4},
        {"first_say_ms": 300, "visible_ms": -1, "pre_say_tokens": 6},
        {"first_say_ms": 200, "pre_say_tokens": 5},
    ]
    summary = lb.summarise(rows)
    assert summary["first_say_ms"]["n"] == 3
    assert summary["first_say_ms"]["median"] == 200
    assert summary["visible_ms"]["n"] == 1, "-1 means 'never landed' and must not count"
    assert summary["pre_say_tokens"]["max"] == 6


def test_load_records_skips_non_turn_lines(tmp_path):
    path = tmp_path / "turns.jsonl"
    path.write_text(
        json.dumps({"event": "start", "session": "s"}) + "\n"
        + json.dumps({"seq": 0, "prompt": [{"role": "system", "content": "x"}],
                      "schema": {"properties": {}}, "output": "{}"}) + "\n",
        encoding="utf-8",
    )
    records = lb.load_records(str(path))
    assert len(records) == 1
    assert records[0]["seq"] == 0


def test_alphabetical_control_run_puts_action_first():
    """Control for DCR-1: with the sorted copy the model starts with `action`."""
    schema = lb.reorder_schema(SCHEMA_COPY, "alphabetical")
    assert list(schema["properties"])[0] == "action"
    assert list(schema["properties"]["beats"]["items"]["properties"]) == [
        "cue", "feeling", "intensity", "say"
    ]


def test_music_fx_beats_first_keeps_the_docs_timing_property():
    """music/fx still precede the beats, so the first line's sound is not late."""
    schema = lb.reorder_schema(SCHEMA_COPY, "music_fx_beats_first")
    assert list(schema["properties"])[:3] == ["music", "fx", "beats"]
    item = schema["properties"]["beats"]["items"]
    assert list(item["properties"])[:4] == ["feeling", "intensity", "cue", "say"]


@pytest.mark.parametrize("order", ["docs", "beats_first", "say_first", "alphabetical", "music_fx_beats_first"])
def test_every_order_offers_the_same_property_set(order):
    schema = lb.reorder_schema(SCHEMA_COPY, order)
    assert set(schema["properties"]) == set(SCHEMA_COPY["properties"])
    assert set(schema["required"]) == set(SCHEMA_COPY["required"])


# --- safety holdback (the visible_on_screen term) -------------------------------

def gd_string(source, name):
    """Read a GDScript string constant, honouring backslash escapes."""
    text = source.split('const %s := "' % name, 1)[1]
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\":
            out.append(text[index + 1])
            index += 2
            continue
        if char == '"':
            break
        out.append(char)
        index += 1
    return "".join(out)


def test_safety_tables_match_the_gdscript_they_mirror():
    """The Python mirror of SafetyText.gd must not drift from the shipped tables."""
    source = (ROOT / "game" / "autoload" / "SafetyText.gd").read_text(encoding="utf-8")
    ascii_sep = gd_string(source, "SEP_ASCII")
    wide_sep = gd_string(source, "SEP_WIDE")
    assert len(ascii_sep) > 10 and len(wide_sep) > 10
    assert set(lb._SAFETY_SEP) == set(ascii_sep + wide_sep)
    leet_block = source.split("const LEET := {", 1)[1].split("}", 1)[0]
    pairs = re.findall(r"(0x[0-9A-Fa-f]+):\s*(0x[0-9A-Fa-f]+)", leet_block)
    assert {int(a, 16): int(b, 16) for a, b in pairs} == lb._SAFETY_LEET


def test_safety_compact_drops_separators_between_letters():
    compact, mapping = lb.safety_compact(lb.safety_normalize("kill yourself", False))
    assert compact == "killyourself"
    assert mapping[0] == 0 and mapping[-1] == 12
    padded, padded_map = lb.safety_compact(lb.safety_normalize("k i l l   y o u r s e l f", False))
    assert padded == "killyourself", "separator padding buys no emission budget"
    assert padded_map[-1] == 24


def test_safety_visible_chars_holds_the_holdback_then_releases():
    assert lb.safety_visible_chars("x" * 33, 34) == 0
    assert lb.safety_visible_chars("x" * 34, 34) == 0
    assert lb.safety_visible_chars("x" * 35, 34) == 1
    # the longest shipped phrase, padded with spaces, still holds: the cut is on
    # compact characters, so separators buy no emission budget
    phrase = "i want to sleep and never wake up"  # the longest shipped phrase
    spaced = " ".join(char for char in phrase if char != " ")
    assert len(spaced) == 51 > 34 and lb.safety_visible_chars(spaced, 34) == 0


def test_safety_visible_chars_matches_the_round1_row0_example():
    """CODE-3's motivating row: the 35th compact char sits at raw character 48.

    `Safety._drain` holds the compact view, so the first displayable character
    lands after more raw characters than the holdback; the raw-char landmark
    reported visible 5363 ms for a row whose own curve puts raw 48 at 5718 ms.
    """
    say = "Um... I'll have the strawberry milk. Do you like that?"
    pending = lb.safety_pending(say)
    compact, mapping = lb.safety_compact(lb.safety_normalize(pending, False))
    assert len(pending) == 54 and len(compact) == 40
    assert mapping[34] == 47, "the 35th compact character is raw character 48"
    assert lb.safety_visible_chars(pending[:47], lb.DEFAULT_HOLDBACK) == 0
    assert lb.safety_visible_chars(pending[:48], lb.DEFAULT_HOLDBACK) == 1


def test_safety_pending_collapses_whitespace_like_say_chunk():
    assert lb.safety_pending("Um,  I  am\tfine\n\nreally") == "Um, I am fine\n\nreally"


# --- run_turn against a stub SSE server (the measurement core) -------------------


def serve_sse(pieces, delay=0.01):
    """Stub llama-server: stream `pieces` as SSE content deltas, then DONE."""

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for piece in pieces:
                chunk = {"choices": [{"delta": {"content": piece}}]}
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
                self.wfile.flush()
                time.sleep(delay)
            timing = {"choices": [], "timings": {"prompt_n": 7, "cache_n": 3,
                                                 "predicted_n": 12, "predicted_per_second": 50.0}}
            self.wfile.write(("data: " + json.dumps(timing) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def turn_text(say_raw):
    return ('{"read":"small_talk","inner":"ok","music":"keep","fx":"none",'
            '"beats":[{"feeling":"shy","intensity":1,"cue":"none","say":"%s"}]}' % say_raw)


def run_against(pieces, holdback=None):
    server = serve_sse(pieces)
    try:
        url = "http://127.0.0.1:%d" % server.server_address[1]
        return lb.run_turn(url, [{"role": "user", "content": "hi"}],
                           {"type": "object", "properties": {}},
                           {"temperature": 0.0}, True,
                           lb.DEFAULT_HOLDBACK if holdback is None else holdback)
    finally:
        server.shutdown()
        server.server_close()


def split_at(text, index):
    return [text[:index], text[index:]]


def test_run_turn_measures_plain_say_from_a_stream():
    text = turn_text("Sit with me, the rain is nice today, don't you think so?")
    result = run_against(split_at(text, len(text) // 2))
    assert result["ok"] is True
    assert result["timings"]["prompt_n"] == 7
    assert result["first_say_ms"] >= 0
    assert result["visible_ms"] >= result["first_say_ms"]
    assert 0 < result["visible_chars"] <= len("Sit with me, the rain is nice today, don't you think so?")
    assert result["visible_raw_ms"] <= result["visible_ms"], "raw chars release earlier"
    assert result["pre_say_text"] == text[:text.index('"say"') + len('"say":"')]


def test_run_turn_finds_a_say_key_split_across_chunks():
    text = turn_text("Sit with me, the rain is nice today, don't you think so?")
    at = text.index('"say"') + 3  # inside the key: `"sa|y":`
    result = run_against(split_at(text, at))
    assert result["ok"] is True
    assert result["first_say_ms"] >= 0, "a split key must not lose the landmark"


def test_run_turn_releases_a_short_say_at_its_closing_quote():
    """A beat shorter than the holdback is released in one go by `Safety.end_say`."""
    result = run_against([turn_text("Um.")])
    assert result["visible_ms"] == result["visible_raw_ms"]
    assert result["visible_chars"] == len("Um.")
    assert result["visible_ms"] >= result["first_say_ms"]


def test_run_turn_does_not_close_the_say_at_an_escaped_quote():
    """CODE-2: `\\"` inside `say` is content, not the closing quote."""
    body = 'She said \\"hi\\" and then she left without another word.'
    text = turn_text(body)
    result = run_against([text[i:i + 8] for i in range(0, len(text), 8)])
    decoded = 'She said "hi" and then she left without another word.'
    assert result["first_say_ms"] >= 0
    # the round-1 parse froze at the escaped quote (9 chars) and stamped
    # `visible_ms` on the chunk that delivered it
    assert result["say_curve"][-1][0] == len(decoded)
    assert result["visible_ms"] >= result["first_say_ms"]
    assert 0 < result["visible_chars"] < len(decoded)


def test_run_turn_reports_a_dead_server_instead_of_raising():
    result = lb.run_turn("http://127.0.0.1:9", [{"role": "user", "content": "hi"}],
                         {"type": "object"}, {"temperature": 0.0}, True, lb.DEFAULT_HOLDBACK)
    assert result["ok"] is False
    assert result["error"] == "transport"
