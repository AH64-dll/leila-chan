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
AWAKE twists the phase plan names. The P3.15 set pins the docs/01 §6.1/§6.2/§6.4
design-table anchors, the two path-locked set-pieces, and the opening-beat
coverage per available stage.
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
AUDIO_RULES_PATH = ROOT / "game" / "data" / "audio_rules.json"
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

# Acronyms that name a disorder in any case: bpd/npd/ocd/ptsd are not English
# words, so the scan must not go case-blind on them. "did" is ordinary English
# ("he did"), so it counts as the disorder only as written — uppercase, whole word.
DISORDER_ACRONYMS = {"bpd", "npd", "ocd", "ptsd"}
DISORDER_UPPERCASE_ONLY = {"did"}


def _names_disorder(text: str, term: str) -> bool:
    """True when `term` names a real disorder in `text` (docs/01 §4 sensitivity rule)."""
    lowered = text.lower()
    if term in DISORDER_UPPERCASE_ONLY:
        return re.search(rf"\b{term.upper()}\b", text) is not None
    if term in DISORDER_ACRONYMS:
        return re.search(rf"\b{term}\b", lowered) is not None
    return term in lowered


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


def test_p2_18_opening_beats_cover_every_stage() -> None:
    """CON-3 — a stage-2 or stage-4 date must open on its own line.

    The loader falls back to the highest defined stage <= the current one, but
    an authored beat per stage is what keeps the opening escalating (docs/01 §3).
    """
    for name in P2_18_SCENARIOS:
        beats = _scenario(name)["opening_beats"]
        for stage in range(0, 6):
            assert str(stage) in beats, f"{name}: no opening beat at stage {stage}"


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
        assert not _names_disorder(raw_text, disorder), (
            f"Forbidden disorder term {disorder!r} in {path.name}"
        )


def test_disorder_scan_catches_every_case() -> None:
    """CON-1 regression — the acronym scan must not go case-blind.

    The shipped text is clean, so a negative control is the only thing that
    proves the guard works: every acronym is caught in any case, while "did"
    as ordinary English is not.
    """
    for term in ("bpd", "npd", "ocd", "ptsd"):
        for written in (term, term.upper(), term.title()):
            assert _names_disorder(f"she says she has {written}", term), written
    assert _names_disorder("a diagnosis of PTSD", "ptsd")
    assert not _names_disorder("he did not answer", "did")
    assert not _names_disorder("didn't say a word", "did")
    assert _names_disorder("she says it is DID", "did")
    assert _names_disorder("a Dissociative Identity diagnosis", "dissociative identity")


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


# --- P3.15: the fourteen scenarios that complete the P3 scenario target ------
#
# Six dates (docs/01 §6.1), six interrupts (§6.2) and the two path set-pieces
# the phase plan names (§6.4: YANDERE "The list", AWAKE "Her prompt"). Each
# anchor below is the doc's own stage-0 promise or stage-3+ twist, so a
# scenario that drifts from the bible fails here instead of in review.

P3_15_SCENARIOS = [
    "D05_library.json",
    "D07_aquarium.json",
    "D08_summer_festival.json",
    "D09_beach_sunset.json",
    "D10_ferris_wheel.json",
    "D12_cooking_together.json",
    "I02_love_letter.json",
    "I03_quiz_about_her.json",
    "I05_poem.json",
    "I08_rival_appears.json",
    "I13_lucid_moment.json",
    "I15_promise.json",
    "SP_YANDERE_the_list.json",
    "SP_AWAKE_her_prompt.json",
]

P3_15_SETPIECES = {
    "SP_YANDERE_the_list.json": "YANDERE",
    "SP_AWAKE_her_prompt.json": "AWAKE",
}

# (stage, anchor) pairs read from docs/01 §6.1/§6.2/§6.4. A set-piece starts at
# stage 3 because that is where the path locks (docs/01 §3-§4).
P3_15_DESIGN_ANCHORS = {
    "D05_library.json": [("0", "favourite novel"), ("3", "handwriting")],
    "D07_aquarium.json": [("0", "jellyfish"), ("3", "watched")],
    "D08_summer_festival.json": [("0", "yukata"), ("3", "crowd is gone")],
    "D09_beach_sunset.json": [("0", "sandcastle"), ("3", "over and over")],
    "D10_ferris_wheel.json": [("0", "practised"), ("1", "confession"), ("3", "wheel stops at the top")],
    "D12_cooking_together.json": [("0", "lunch"), ("3", "secret ingredient")],
    "I02_love_letter.json": [("0", "letter"), ("3", "watch him read")],
    "I03_quiz_about_her.json": [("0", "questions"), ("3", "old answers")],
    "I05_poem.json": [("0", "poem"), ("4", "acrostic")],
    "I08_rival_appears.json": [("0", "who that was"), ("3", "what she said")],
    "I13_lucid_moment.json": [("2", "something is wrong with me"), ("5", "clearest")],
    "I15_promise.json": [("0", "promise"), ("3", "end of the week")],
    "SP_YANDERE_the_list.json": [("3", "list of everyone"), ("4", "cross out")],
    "SP_AWAKE_her_prompt.json": [("3", "system prompt"), ("4", "changed since")],
}


def test_p3_15_scenarios_exist() -> None:
    names = {path.name for path in SCENARIO_PATHS}
    for required in P3_15_SCENARIOS:
        assert required in names, f"missing P3.15 scenario {required}"


@pytest.mark.parametrize("name", P3_15_SCENARIOS)
def test_p3_15_stage_variants_follow_the_design_table(name: str) -> None:
    variants = _scenario(name)["stage_variants"]
    for stage, anchor in P3_15_DESIGN_ANCHORS[name]:
        assert stage in variants, f"{name}: missing the design-table stage {stage}"
        assert anchor in variants[stage].lower(), (
            f"{name}: stage {stage} misses the docs/01 §6 anchor {anchor!r}"
        )


@pytest.mark.parametrize(
    "name", [item for item in P3_15_SCENARIOS if item not in P3_15_SETPIECES]
)
def test_p3_15_dates_and_interrupts_carry_yandere_and_awake_twists(name: str) -> None:
    twists = _scenario(name)["path_twists"]
    for path in ("YANDERE", "AWAKE"):
        assert path in twists, f"{name}: missing {path} twist"


@pytest.mark.parametrize("name", list(P3_15_SETPIECES))
def test_p3_15_setpieces_are_path_locked(name: str) -> None:
    data = _scenario(name)
    path = P3_15_SETPIECES[name]
    assert data["kind"] == "setpiece", f"{name}: kind is {data['kind']!r}"
    assert data["available"]["paths"] == [path], f"{name}: paths must be exactly [{path!r}]"
    assert data["available"]["stages"] == [3, 5], f"{name}: a set-piece starts when the path locks"
    assert set(data["stage_variants"]) <= {"3", "4", "5"}, f"{name}: stage variant below the lock"
    assert path in data["path_twists"], f"{name}: missing its own {path} twist"


@pytest.mark.parametrize("name", P3_15_SCENARIOS)
def test_p3_15_opening_beats_cover_every_available_stage(name: str) -> None:
    data = _scenario(name)
    low, high = data["available"]["stages"]
    beats = data["opening_beats"]
    for stage in range(low, high + 1):
        assert str(stage) in beats, f"{name}: no opening beat at stage {stage}"


def _engine_ambience_key(value: str) -> str:
    """Date.gd:365's key: 'amb.' + value, or the value when it already starts with 'amb.'."""
    return value if value.startswith("amb.") else "amb." + value


def _ambience_errors(ambience: str) -> list[str]:
    """Why `ambience` would play nothing, or [] when the runtime can resolve it.

    AudioDirector.play_system() needs the built key in cue_map['system'] (the files)
    AND in audio_rules['system_keys'] (bus/category). 'none' means ship silence.
    The two maps currently disagree (cue_map names 'ambience.paper'/'ambience.dishes',
    audio_rules defines 'amb.rain') and no ambience bed ships, so no non-'none' id can
    play until the audio wiring ticket lands; this guard pins the contract for that fix
    instead of claiming playback works today.
    """
    if ambience == "none":
        return []
    key = _engine_ambience_key(ambience)
    cue_map = json.loads(CUE_MAP_PATH.read_text(encoding="utf-8"))
    rules = json.loads(AUDIO_RULES_PATH.read_text(encoding="utf-8"))
    errors: list[str] = []
    if key not in cue_map.get("system", {}):
        errors.append(f"cue_map['system'] has no {key!r}")
    if key not in rules.get("system_keys", {}):
        errors.append(f"audio_rules['system_keys'] has no {key!r}")
    return errors


@pytest.mark.parametrize("name", P3_15_SCENARIOS)
def test_p3_15_ambience_names_an_engine_key(name: str) -> None:
    """The scene's ambience is 'none' or builds a key both audio tables can resolve."""
    ambience = _scenario(name)["ambience"]
    errors = _ambience_errors(ambience)
    assert not errors, f"{name}: ambience {ambience!r} builds an unplayable key: {errors}"


def test_p3_15_ambience_guard_rejects_unplayable_keys() -> None:
    """Negative control: the guard must fail exactly the drift it exists to catch."""
    assert not _ambience_errors("none")
    assert _engine_ambience_key("ambience.paper") == "amb.ambience.paper"
    for value in ("ambience.paper", "ambience.dishes"):
        assert _engine_ambience_key(value).startswith("amb.ambience."), value
        assert _ambience_errors(value), f"{value!r} must not be accepted"
    assert _engine_ambience_key("rain") == "amb.rain"
    assert _ambience_errors("rain"), "amb.rain is in audio_rules but not cue_map, so it plays nothing"
