"""Tests for tools/llm/latency_breakdown.py (P2.26 first-beat latency harness).

The harness replays the prompts a real date sent and decomposes the time before
the first usable `say`. These tests pin the two parts that decide what it
measures — the schema order it puts on the wire and the ordering sentence it
patches — plus the safety holdback it assumes. They need no llama-server.
"""

import json
import sys
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

SYSTEM = (
    "You are Leila.\n"
    "Respond ONLY with JSON in this exact order:\n"
    "read: label what the player just did (one word from the list).\n"
    "inner: your private gut reaction, max 15 words.\n"
)


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


def test_messages_without_the_sentence_are_left_alone():
    messages = [{"role": "system", "content": "no instruction here"},
                {"role": "user", "content": "hi"}]
    assert lb.patch_system_order(messages, "say_first") == messages


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
