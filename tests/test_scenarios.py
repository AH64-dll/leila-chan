"""Unit and contract tests for scenario definitions and schemas (P1.15, P2.18).

Guards docs/08 §7 format and the NAR craft rules for every scenario in
`game/data/scenarios/`:

- validates against `game/data/schemas/scenario.schema.json` (the validation is
  schema-driven: required keys, types, enums, patterns, bounds, oneOf,
  additionalProperties, propertyNames — a new schema keyword the validator does
  not understand fails the negative tests below)
- stage 3 and 5 variants exist (role playbook), path twists stay canonical and
  plentiful, opening beats are playable at their stage
- sensitivity and brand rules (no real disorder named, no banned brands)
- `{player_name}` is the only placeholder

The P2.18 set (D01, D03, D04, D06, D11, I01) additionally pins the YANDERE and
AWAKE twists the phase plan names.
"""

import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_DIR = ROOT / "game" / "data" / "scenarios"
SCHEMAS_DIR = ROOT / "game" / "data" / "schemas"
SCHEMA_PATH = SCHEMAS_DIR / "scenario.schema.json"

CASTING_PATH = ROOT / "data" / "casting.json"
CUE_MAP_PATH = ROOT / "assets" / "audio" / "cue_map.json"
STAGE_GATES_PATH = ROOT / "game" / "data" / "stage_gates.json"

SCENARIO_PATHS = sorted(SCENARIOS_DIR.glob("*.json"))

# P2.18 — the five dates + one interrupt this task adds (docs/01 §6.1/§6.2).
P2_18_SCENARIOS = [
    "D01_classroom.json",
    "D03_park_bench.json",
    "D04_rain_umbrella.json",
    "D06_rooftop.json",
    "D11_her_room.json",
    "I01_phone_call.json",
]

CANONICAL_PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
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

# Terms that must appear as written (uppercase whole word) to count as a named
# disorder: the lowercase spellings are ordinary English words.
DISORDER_ACRONYMS = {"bpd", "did", "npd", "ocd", "ptsd"}

JSON_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
}


def _json_type_ok(value, expected: str) -> bool:
    kind = JSON_TYPES.get(expected)
    if kind is None:
        return True
    if expected == "boolean":
        return isinstance(value, bool)
    if expected in ("integer", "number"):
        return isinstance(value, kind) and not isinstance(value, bool)
    return isinstance(value, kind)


def _schema_errors(value, schema: dict, where: str = "$") -> list[str]:
    """Validate `value` against the subset of JSON Schema the scenario schema uses."""
    if not isinstance(schema, dict):
        return []
    errors: list[str] = []
    expected = schema.get("type")
    if expected is not None:
        types = expected if isinstance(expected, list) else [expected]
        if not any(_json_type_ok(value, t) for t in types):
            return [f"{where}: expected {expected}, got {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: {value!r} is not one of {schema['enum']}")
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{where}: shorter than {schema['minLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{where}: does not match {schema['pattern']!r}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{where}: {value} < minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{where}: {value} > maximum {schema['maximum']}")
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{where}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{where}: more than {schema['maxItems']} items")
        if "items" in schema:
            for index, item in enumerate(value):
                errors.extend(_schema_errors(item, schema["items"], f"{where}[{index}]"))
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{where}: missing required property {key!r}")
        if "propertyNames" in schema:
            for key in value:
                errors.extend(_schema_errors(key, schema["propertyNames"], f"{where}.<key>"))
        properties = schema.get("properties", {})
        for key, item in value.items():
            if key in properties:
                errors.extend(_schema_errors(item, properties[key], f"{where}.{key}"))
                continue
            extra = schema.get("additionalProperties", True)
            if extra is False:
                errors.append(f"{where}: unexpected property {key!r}")
            elif isinstance(extra, dict):
                errors.extend(_schema_errors(item, extra, f"{where}.{key}"))
    if "oneOf" in schema:
        matches = [not _schema_errors(value, sub, where) for sub in schema["oneOf"]]
        if matches.count(True) != 1:
            errors.append(f"{where}: matches {matches.count(True)} of oneOf, expected exactly 1")
    return errors


def _scenario(name: str) -> dict:
    return json.loads((SCENARIOS_DIR / name).read_text(encoding="utf-8"))


def _scenario_text(data: dict) -> str:
    """Every player- or model-visible string in the scenario, for rule scans."""
    texts = [data["title"], data["goal"], data["prompt"]]
    texts.extend(data["stage_variants"].values())
    texts.extend(data["path_twists"].values())
    for beats in data.get("opening_beats", {}).values():
        texts.extend(beat.get("say", "") for beat in beats)
    texts.extend(event.get("line", "") for event in data["events"])
    return "\n".join(texts)


def test_scenario_schema_file_exists_and_valid_json() -> None:
    assert SCHEMA_PATH.exists(), f"Missing schema at {SCHEMA_PATH}"
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert schema.get("$schema"), "Missing $schema declaration"
    assert "required" in schema
    assert "properties" in schema


def test_scenarios_exist() -> None:
    names = {path.name for path in SCENARIO_PATHS}
    for required in P2_18_SCENARIOS:
        assert required in names, f"missing scenario {required}"


def test_schema_validator_rejects_broken_scenarios() -> None:
    """The validator must fail bad data — a schema test that passes anything is useless."""
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    good = _scenario("D02_cafe.json")
    assert not _schema_errors(good, schema)

    missing = json.loads(json.dumps(good))
    del missing["goal"]
    assert _schema_errors(missing, schema), "missing required key not caught"

    bad_kind = json.loads(json.dumps(good))
    bad_kind["kind"] = "cutscene"
    assert _schema_errors(bad_kind, schema), "invalid kind not caught"

    extra = json.loads(json.dumps(good))
    extra["deleted_scene"] = True
    assert _schema_errors(extra, schema), "additionalProperties:false not caught"

    bad_variant = json.loads(json.dumps(good))
    bad_variant["stage_variants"]["3"] = 3
    assert _schema_errors(bad_variant, schema), "non-string stage variant not caught"

    bad_twist = json.loads(json.dumps(good))
    bad_twist["path_twists"]["OBSESSION"] = "not canonical"
    assert _schema_errors(bad_twist, schema), "non-canonical path twist not caught"

    bad_beat = json.loads(json.dumps(good))
    bad_beat["opening_beats"]["0"][0]["intensity"] = 0
    assert _schema_errors(bad_beat, schema), "out-of-range intensity not caught"

    bad_days = json.loads(json.dumps(good))
    bad_days["available"]["days"] = [1]
    assert _schema_errors(bad_days, schema), "one-item days array not caught"

    bad_paths = json.loads(json.dumps(good))
    bad_paths["available"]["paths"] = 7
    assert _schema_errors(bad_paths, schema), "numeric paths value not caught"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_validates_against_schema(path: Path) -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    data = json.loads(path.read_text(encoding="utf-8"))
    errors = _schema_errors(data, schema)
    assert not errors, f"Validation errors in {path.name}: {errors}"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_id_matches_filename(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["id"] == path.stem, f"{path.name}: id {data['id']!r} != filename"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_has_stage_3_and_5_variants(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    variants = data["stage_variants"]
    assert "3" in variants, f"{path.name}: missing stage 3 variant"
    assert "5" in variants, f"{path.name}: missing stage 5 variant"
    low, high = data["available"]["stages"]
    for key, text in variants.items():
        assert key.isdigit() and 0 <= int(key) <= 5, f"{path.name}: bad stage key {key!r}"
        assert low <= int(key) <= high, f"{path.name}: stage {key} outside available.stages"
        assert text.strip(), f"{path.name}: empty stage variant {key}"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_has_two_path_twists(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    twists = data["path_twists"]
    assert len(twists) >= 2, f"{path.name}: expected >= 2 path twists, got {len(twists)}"
    for name in twists:
        assert name in CANONICAL_PATHS, f"{path.name}: non-canonical twist {name!r}"


def test_p2_18_scenarios_carry_yandere_and_awake_twists() -> None:
    for name in P2_18_SCENARIOS:
        twists = _scenario(name)["path_twists"]
        assert "YANDERE" in twists, f"{name}: missing YANDERE twist"
        assert "AWAKE" in twists, f"{name}: missing AWAKE twist"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_opening_beats(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    feelings = set(json.loads(CASTING_PATH.read_text(encoding="utf-8"))["feelings"])
    cues = set(json.loads(CUE_MAP_PATH.read_text(encoding="utf-8"))["cues"])
    cues.add("none")
    stage_gates = json.loads(STAGE_GATES_PATH.read_text(encoding="utf-8"))["stages"]

    for stage_key, beats in data.get("opening_beats", {}).items():
        assert stage_key.isdigit() and 0 <= int(stage_key) <= 5, (
            f"{path.name}: bad opening_beats key {stage_key!r}"
        )
        allowed_cues = set(stage_gates[stage_key]["cues"])
        assert beats, f"{path.name}: empty opening_beats at stage {stage_key}"
        for beat in beats:
            assert beat["feeling"] in feelings, f"{path.name}: invalid feeling {beat['feeling']!r}"
            cue = beat.get("cue", "none")
            assert cue in cues, f"{path.name}: unknown cue {cue!r}"
            assert cue == "none" or cue in allowed_cues, (
                f"{path.name}: cue {cue!r} is not playable at stage {stage_key}"
            )
            assert 1 <= beat["intensity"] <= 3, f"{path.name}: bad intensity {beat['intensity']}"
            sentences = [s for s in re.split(r"[.!?]+", beat["say"]) if s.strip()]
            assert len(sentences) <= 2, f"{path.name}: opening beat exceeds 2 sentences: {beat['say']}"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_events_and_bounds(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    end = data["end"]
    assert end["min_turns"] <= end["max_turns"], f"{path.name}: min_turns > max_turns"
    assert data["events"], f"{path.name}: no events"
    for event in data["events"]:
        assert event.get("line", "").strip(), f"{path.name}: event without a line"
        triggers = [key for key in ("at_turn", "on_trigger") if key in event]
        assert len(triggers) == 1, f"{path.name}: event needs exactly one of at_turn/on_trigger"
        if "at_turn" in event:
            assert int(event["at_turn"]) <= end["max_turns"], (
                f"{path.name}: at_turn {event['at_turn']} after max_turns"
            )
        else:
            assert re.fullmatch(r"T\d{2}", event["on_trigger"]), (
                f"{path.name}: bad trigger id {event['on_trigger']!r}"
            )


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_sensitivity_and_brands(path: Path) -> None:
    raw_text = path.read_text(encoding="utf-8")
    lowered = raw_text.lower()
    for brand in FORBIDDEN_BRANDS:
        assert brand not in lowered, f"Forbidden brand '{brand}' found in {path.name}"
    for disorder in FORBIDDEN_DISORDERS:
        # The short acronyms collide with ordinary English ("did", "he did"):
        # they name the disorder only as written — uppercase, whole word.
        # The long forms still match anywhere, case-insensitively.
        if disorder in DISORDER_ACRONYMS:
            assert not re.search(rf"\b{disorder.upper()}\b", raw_text), (
                f"Forbidden disorder acronym '{disorder.upper()}' in {path.name}"
            )
        else:
            assert disorder not in lowered, f"Forbidden disorder term '{disorder}' in {path.name}"


@pytest.mark.parametrize("path", SCENARIO_PATHS, ids=lambda p: p.stem)
def test_scenario_placeholders(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    pattern = re.compile(r"\{([^}]+)\}")
    for text in _scenario_text(data).split("\n"):
        for match in pattern.findall(text):
            assert match == "player_name", f"Unexpected placeholder '{{{match}}}' in {path.name}"


def test_d02_narrative_variants_and_twists() -> None:
    d02 = _scenario("D02_cafe.json")
    variants = d02["stage_variants"]
    for stage in ("0", "1", "2", "3", "5"):
        assert stage in variants, f"Missing stage {stage} variant in D02_cafe.json"
    assert "sweet drinks" in variants["0"] or "likes" in variants["0"]
    assert "already ordered" in variants["1"]
    assert "wrote his order" in variants["2"] or "normal thing" in variants["2"]
    twists = d02["path_twists"]
    assert "YANDERE" in twists, "Expected YANDERE path twist"
    assert "HOLLOW" in twists or "AWAKE" in twists


def test_p2_18_stage_variants_follow_the_design_table() -> None:
    """docs/01 §6.1's stage-0 goal and stage-3+ twist must be visible in the data."""
    checks = {
        "D01_classroom.json": ("know", "before"),
        "D03_park_bench.json": ("count", "missing"),
        "D04_rain_umbrella.json": ("shoulder", "umbrella"),
        "D06_rooftop.json": ("secret", "fence"),
        "D11_her_room.json": ("plushie", "photos"),
        "I01_phone_call.json": ("friend", "no one on the line"),
    }
    for name, (stage_0_anchor, stage_3_anchor) in checks.items():
        data = _scenario(name)
        assert stage_0_anchor in data["stage_variants"]["0"].lower(), f"{name}: stage 0 misses design"
        assert stage_3_anchor in data["stage_variants"]["3"].lower(), f"{name}: stage 3 misses design"
