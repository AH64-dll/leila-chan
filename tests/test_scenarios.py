"""Unit and contract tests for scenario definitions and schemas (P1.15).

Guards docs/08 §7 format, schema validation, and narrative craft rules:
- D02 café validates against game/data/schemas/scenario.schema.json
- Required fields, turn ranges, and stage variants
- Opening beats follow prompt rules (valid feelings, cues, <= 2 sentences)
- Sensitivity and brand rules (no real disorder names, no banned brands)
"""

import json
import re
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_DIR = ROOT / "game" / "data" / "scenarios"
SCHEMAS_DIR = ROOT / "game" / "data" / "schemas"
SCHEMA_PATH = SCHEMAS_DIR / "scenario.schema.json"
D02_PATH = SCENARIOS_DIR / "D02_cafe.json"

CASTING_PATH = ROOT / "data" / "casting.json"
CUE_MAP_PATH = ROOT / "assets" / "audio" / "cue_map.json"

FORBIDDEN_BRANDS = ["qwen", "chatgpt", "gpt-4", "claude", "gemini", "llama", "deepseek"]
FORBIDDEN_DISORDERS = [
    "bpd",
    "borderline",
    "bipolar",
    "schizo",
    "autis",
    "asperger",
    "did",
    "dissociative identity",
    "npd",
    "narcissis",
    "ocd",
    "ptsd",
    "depression",
    "depressed",
    "sociopath",
    "psychopath",
]


def _validate_scenario_structure(data: dict, schema: dict) -> list[str]:
    """Lightweight structural validator matching scenario.schema.json contract."""
    errors = []
    # Check top-level required properties
    for req in schema.get("required", []):
        if req not in data:
            errors.append(f"Missing required property: {req}")

    if data.get("kind") not in schema["properties"]["kind"]["enum"]:
        errors.append(f"Invalid kind: {data.get('kind')}")

    avail = data.get("available", {})
    if not isinstance(avail, dict):
        errors.append("available must be an object")
    else:
        days = avail.get("days", [])
        if not (isinstance(days, list) and len(days) == 2 and days[0] <= days[1]):
            errors.append(f"Invalid available.days: {days}")
        stages = avail.get("stages", [])
        if not (isinstance(stages, list) and len(stages) == 2 and 0 <= stages[0] <= stages[1] <= 5):
            errors.append(f"Invalid available.stages: {stages}")

    end_rules = data.get("end", {})
    if not isinstance(end_rules, dict):
        errors.append("end must be an object")
    else:
        min_turns = end_rules.get("min_turns")
        max_turns = end_rules.get("max_turns")
        if not (isinstance(min_turns, int) and min_turns >= 1):
            errors.append(f"Invalid end.min_turns: {min_turns}")
        if not (isinstance(max_turns, int) and max_turns >= 1):
            errors.append(f"Invalid end.max_turns: {max_turns}")
        if isinstance(min_turns, int) and isinstance(max_turns, int) and max_turns < min_turns:
            errors.append(f"end.max_turns ({max_turns}) < min_turns ({min_turns})")
        if not end_rules.get("on_goal"):
            errors.append("Missing end.on_goal")

    if not isinstance(data.get("events"), list):
        errors.append("events must be an array")
    if not isinstance(data.get("stage_variants"), dict):
        errors.append("stage_variants must be an object")
    if not isinstance(data.get("path_twists"), dict):
        errors.append("path_twists must be an object")

    return errors


def test_scenario_schema_file_exists_and_valid_json() -> None:
    assert SCHEMA_PATH.exists(), f"Missing schema at {SCHEMA_PATH}"
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert schema.get("$schema"), "Missing $schema declaration"
    assert "required" in schema
    assert "properties" in schema


def test_d02_cafe_validates_against_schema() -> None:
    assert D02_PATH.exists(), f"Missing D02 scenario at {D02_PATH}"
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    d02 = json.loads(D02_PATH.read_text(encoding="utf-8"))

    errors = _validate_scenario_structure(d02, schema)
    assert not errors, f"Validation errors in D02_cafe.json: {errors}"


def test_d02_narrative_variants_and_twists() -> None:
    d02 = json.loads(D02_PATH.read_text(encoding="utf-8"))

    # Stage 0 and 1 variants required for P1.15
    variants = d02["stage_variants"]
    assert "0" in variants, "Missing stage 0 variant in D02_cafe.json"
    assert "1" in variants, "Missing stage 1 variant in D02_cafe.json"
    assert "3" in variants, "Missing stage 3 variant in D02_cafe.json"
    assert "5" in variants, "Missing stage 5 variant in D02_cafe.json"

    # Stage 0: asks what he likes / Stage 1: already ordered
    assert "sweet drinks" in variants["0"] or "likes" in variants["0"]
    assert "already ordered" in variants["1"]

    # Role playbook requires at least 2 path twists
    twists = d02["path_twists"]
    assert len(twists) >= 2, f"Expected >= 2 path twists, got {len(twists)}"
    assert "HOLLOW" in twists or "AWAKE" in twists


def test_d02_opening_beats() -> None:
    d02 = json.loads(D02_PATH.read_text(encoding="utf-8"))
    assert "opening_beats" in d02, "D02_cafe.json missing opening_beats"

    opening = d02["opening_beats"]
    assert "0" in opening, "Missing stage 0 opening beats"
    assert "1" in opening, "Missing stage 1 opening beats"

    casting = json.loads(CASTING_PATH.read_text(encoding="utf-8"))
    feelings = set(casting["feelings"].keys())

    cue_map = json.loads(CUE_MAP_PATH.read_text(encoding="utf-8"))
    cues = set(cue_map["cues"].keys())
    cues.add("none")

    for stage_key in ("0", "1"):
        beats = opening[stage_key]
        assert len(beats) >= 1
        for b in beats:
            assert b["feeling"] in feelings, f"Invalid feeling: {b['feeling']}"
            assert b.get("cue", "none") in cues, f"Invalid cue: {b.get('cue')}"
            assert 1 <= b["intensity"] <= 3
            # Sentence count rule: <= 2 sentences
            say = b["say"]
            sentences = [s.strip() for s in re.split(r"[.!?]+", say) if s.strip()]
            assert len(sentences) <= 2, f"Opening beat say exceeds 2 sentences: {say}"


def test_d02_content_sensitivity_and_brands() -> None:
    raw_text = D02_PATH.read_text(encoding="utf-8").lower()

    for brand in FORBIDDEN_BRANDS:
        assert brand not in raw_text, f"Forbidden brand '{brand}' found in D02_cafe.json"

    for disorder in FORBIDDEN_DISORDERS:
        assert disorder not in raw_text, f"Forbidden disorder term '{disorder}' in D02_cafe.json"


def test_d02_placeholders() -> None:
    d02 = json.loads(D02_PATH.read_text(encoding="utf-8"))
    # Check that placeholders use {player_name} and not raw names or different brackets
    text_corpus = [
        d02["prompt"],
        d02["goal"],
        *d02["stage_variants"].values(),
        *d02["path_twists"].values(),
    ]
    for stage_beats in d02.get("opening_beats", {}).values():
        for b in stage_beats:
            text_corpus.append(b.get("say", ""))

    pattern = re.compile(r"\{([^}]+)\}")
    for text in text_corpus:
        matches = pattern.findall(text)
        for m in matches:
            assert m == "player_name", f"Unexpected placeholder '{{{m}}}' in text: {text}"
