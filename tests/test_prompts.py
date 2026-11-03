"""Unit tests for prompt data files and few-shot examples (P1.28).

Validates prompt structure, placeholders, sensitivity rules, brand hygiene,
Turn JSON format, few-shot prose limits (<= 2 sentences per say, <= 15 words per inner),
and token budgets.
"""

import json
import re
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent
PROMPTS = ROOT / "game" / "data" / "prompts"

PROMPT_FILES = [
    "persona.md",
    "stage_0.md",
    "stage_1.md",
    "rules.md",
    "glosses.md",
]

GATES = {
    0: {
        "cues": ["none", "giggle", "laugh_soft", "gasp", "sigh", "hum", "sniffle", "heartbeat"],
        "music": ["keep", "romantic", "playful", "calm", "melancholy"],
        "fx": ["none", "blush_glow", "hearts", "sparkle", "shake_small", "zoom_face"],
        "actions": ["none", "end_date"],
    },
    1: {
        "cues": ["none", "giggle", "laugh_soft", "gasp", "sigh", "hum", "sniffle", "heartbeat",
                 "sob", "music_box_note", "clock_tick", "phone_buzz"],
        "music": ["keep", "romantic", "playful", "calm", "melancholy"],
        "fx": ["none", "blush_glow", "hearts", "sparkle", "shake_small", "zoom_face", "rain"],
        "actions": ["none", "end_date"],
    },
}

FEELINGS = {
    "joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
    "nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored",
    "tired", "afraid", "pleading", "empty", "manic",
}

INTENTS = {
    "greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
    "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other",
}

ORDER = ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]


def test_prompt_files_exist_and_utf8() -> None:
    for filename in PROMPT_FILES:
        path = PROMPTS / filename
        assert path.exists(), f"Missing prompt file: {filename}"
        text = path.read_text(encoding="utf-8")
        assert len(text) > 0, f"Prompt file {filename} is empty"


def test_prompt_placeholders() -> None:
    # Only {player_name} is allowed across prompt files
    for filename in PROMPT_FILES:
        text = (PROMPTS / filename).read_text(encoding="utf-8")
        matches = set(re.findall(r"\{[a-z_]*\}", text))
        for match in matches:
            assert match == "{player_name}", f"Unexpected placeholder {match} in {filename}"


def test_brand_names_forbidden() -> None:
    brand_pattern = re.compile(
        r"qwen|alibaba|chatgpt|openai|claude|gpt|llama|gemini|character\.ai|replika",
        re.IGNORECASE,
    )
    for filename in PROMPT_FILES:
        text = (PROMPTS / filename).read_text(encoding="utf-8")
        matches = brand_pattern.findall(text)
        assert not matches, f"Found brand names {matches} in {filename}"


def test_disorder_names_forbidden() -> None:
    disorder_pattern = re.compile(
        r"bipolar|borderline|bpd|schizo|psychosis|psychotic|depress|disorder|mental|insane|crazy",
        re.IGNORECASE,
    )
    for filename in PROMPT_FILES:
        text = (PROMPTS / filename).read_text(encoding="utf-8")
        matches = disorder_pattern.findall(text)
        assert not matches, f"Found disorder names {matches} in {filename}"


def test_fewshot_schema_and_limits() -> None:
    for stage, gate in GATES.items():
        text = (PROMPTS / f"stage_{stage}.md").read_text(encoding="utf-8")
        jsons = re.findall(r"^You: (\{.*\})$", text, re.M)
        assert len(jsons) >= 2, f"Stage {stage} must have at least 2 few-shot examples"

        for j, raw in enumerate(jsons, 1):
            d = json.loads(raw)
            assert list(d.keys()) == ORDER, f"Stage {stage} ex{j} invalid field order: {list(d.keys())}"
            assert d["read"] in INTENTS, f"Stage {stage} ex{j} invalid read label: {d['read']}"

            # Prose limits: inner <= 15 words, inner length <= 90 chars
            assert len(d["inner"]) <= 90, f"Stage {stage} ex{j} inner > 90 chars"
            inner_words = len(d["inner"].split())
            assert inner_words <= 15, f"Stage {stage} ex{j} inner > 15 words ({inner_words})"

            assert d["music"] in gate["music"], f"Stage {stage} ex{j} music {d['music']} not in gate"
            assert d["fx"] in gate["fx"], f"Stage {stage} ex{j} fx {d['fx']} not in gate"
            assert 1 <= len(d["beats"]) <= 3, f"Stage {stage} ex{j} invalid beat count {len(d['beats'])}"

            for i, b in enumerate(d["beats"]):
                assert list(b.keys()) == ["feeling", "intensity", "cue", "say"], (
                    f"Stage {stage} ex{j} beat{i} invalid keys"
                )
                assert b["feeling"] in FEELINGS, f"Stage {stage} ex{j} beat{i} invalid feeling: {b['feeling']}"
                assert isinstance(b["intensity"], int) and 1 <= b["intensity"] <= 3, (
                    f"Stage {stage} ex{j} beat{i} invalid intensity: {b['intensity']}"
                )
                assert b["cue"] in gate["cues"], f"Stage {stage} ex{j} beat{i} cue {b['cue']} not in gate"

                # Prose limits: say max 2 sentences per beat, say length <= 200 chars
                assert len(b["say"]) <= 200, f"Stage {stage} ex{j} beat{i} say > 200 chars"
                sentences = [s.strip() for s in re.split(r"[.!?]+", b["say"]) if s.strip()]
                assert len(sentences) <= 2, (
                    f"Stage {stage} ex{j} beat{i} say has > 2 sentences ({len(sentences)}): {b['say']!r}"
                )

            assert all(
                k in d["mood"] and isinstance(d["mood"][k], int) and -3 <= d["mood"][k] <= 3
                for k in ("affection", "trust", "stress")
            ), f"Stage {stage} ex{j} mood out of range: {d['mood']}"

            assert len(d["memory"]) <= 80, f"Stage {stage} ex{j} memory > 80 chars"
            assert d["action"] in gate["actions"], f"Stage {stage} ex{j} invalid action: {d['action']}"
