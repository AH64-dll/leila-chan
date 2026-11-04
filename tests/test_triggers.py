"""P2.08 — pin the docs/01 §5 trigger catalogue the engine reads.

The GDScript suite (game/tests/TriggersTest.gd) proves the engine's behaviour;
this file guards the *table* a reviewer reads without a Godot build. Three
things are worth a separate file: the strength weights are docs/02 §1.2's
agreement rule and not a code constant, every row is a legal row of the
vocabulary TriggerEngine implements (a typo becomes a skipped trigger, and a
skipped trigger is invisible in play), and the E rows agree with
data/telemetry.json — two self-consistent files that disagree is exactly the
bug neither side's own tests can see.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRIGGERS_FILE = ROOT / "game" / "data" / "triggers.json"
TRIGGERS = json.loads(TRIGGERS_FILE.read_text(encoding="utf-8"))
TELEMETRY = json.loads((ROOT / "game" / "data" / "telemetry.json").read_text(encoding="utf-8"))
PROFILE_MAP = json.loads((ROOT / "game" / "data" / "profile_map.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
DIRECTOR = (ROOT / "docs" / "02_DIRECTOR_PROTOCOL.md").read_text(encoding="utf-8")

# GameState.gd's meter names and GameState.PATHS (docs/01 §2, §4).
METER_NAMES = {"affection", "trust", "instability", "fixation", "lucidity"}
PATHS = {"YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"}
# docs/01 §2 behaviour-profile counters.
PROFILE_COUNTERS = {
    "warmth",
    "coldness",
    "inconsistency",
    "teasing",
    "jealousy_bait",
    "leaving_talk",
    "meta_curiosity",
    "honesty",
    "boundaries",
    "apathy",
    "control",
    "flattery",
}
# TriggerEngine's vocabulary.
BEHAVIORS = {"once", "repeatable", "escalating"}
REQUIRES = {"any", "all"}
ESCALATION_AXES = {"step", "stage"}
DETECTORS = {"keyword", "model", "event", "clock"}
DETECTOR_LETTERS = {"keyword": "K", "model": "M", "event": "E", "clock": "C"}
LINE_TOKENS = {"count", "ordinal", "stage", "day", "turn"}

TRIGGER_ROWS = TRIGGERS["triggers"]
DEFAULTS = TRIGGERS["defaults"]


def _doc_table() -> dict:
    """docs/01 §5's trigger table: id -> {"detect": {K,M,E,C}, ...}."""
    table = {}
    pattern = re.compile(r"^\|\s*(T\d\d)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|")
    for line in DESIGN.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        table[match.group(1)] = {
            "text": match.group(2).strip(),
            "detect": set(re.findall(r"[KMEC]", match.group(3))),
            "effect": match.group(4).strip(),
        }
    return table


DOC_TRIGGERS = _doc_table()


def _field(row: dict, key: str):
    """A row's value, or the engine default the loader would fall back to."""
    return row[key] if key in row else DEFAULTS[key]


def test_doc_tables_are_parsed() -> None:
    assert len(DOC_TRIGGERS) == 32, "docs/01 §5 has T01–T32"
    assert DOC_TRIGGERS["T01"]["detect"] == {"K", "M"}
    assert DOC_TRIGGERS["T04"]["detect"] == {"C"}
    assert "Every trigger has **once / repeatable / escalating** behavior" in DESIGN
    assert "model-only → half strength" in DIRECTOR


def test_shape_and_strength_are_the_agreement_rule() -> None:
    assert set(TRIGGERS) == {"version", "doc", "strength", "defaults", "triggers"}
    assert TRIGGERS["version"] == 1
    assert TRIGGERS["doc"].strip(), "triggers.json carries no doc string"
    strength = TRIGGERS["strength"]
    # docs/02 §1.2: "when both agree, the trigger fires with full strength;
    # model-only → half strength".
    assert strength["agreement"] == 1.0
    assert strength["model"] == 0.5
    # A keyword is deterministic evidence, and docs/01 §5 has K-only rows
    # (T02, T06, T07…), so keyword-only must be able to reach full strength.
    assert strength["keyword"] == 1.0
    assert strength["engine"] == 1.0
    assert strength["clock"] == 1.0


def test_defaults_cover_the_engine_vocabulary() -> None:
    assert set(DEFAULTS) == {
        "requires",
        "behavior",
        "cooldown_turns",
        "stage_min",
        "stage_max",
        "escalate",
    }
    assert DEFAULTS["requires"] in REQUIRES
    assert DEFAULTS["behavior"] in BEHAVIORS
    assert isinstance(DEFAULTS["cooldown_turns"], int)
    assert DEFAULTS["cooldown_turns"] >= 0
    assert 0 <= DEFAULTS["stage_min"] <= DEFAULTS["stage_max"] <= 5
    assert DEFAULTS["escalate"]["max_steps"] >= 2
    assert DEFAULTS["escalate"]["step_scale"] > 0
    # The default axis is the firing count: only docs/01 §5 T08 escalates with
    # the stage, so a row opts in.
    assert DEFAULTS["escalate"]["axis"] == "step"


def test_every_row_is_a_legal_row() -> None:
    assert TRIGGER_ROWS, "the catalogue ships at least the E rows P2.09 detects"
    for trigger_id, row in TRIGGER_ROWS.items():
        assert re.fullmatch(r"T\d\d", trigger_id), f"{trigger_id!r} is not a Tnn id"
        assert row["name"].strip(), f"{trigger_id} has no name"
        detect = row["detect"]
        assert isinstance(detect, dict) and detect, f"{trigger_id} has no detector"
        assert set(detect) <= DETECTORS, f"{trigger_id} uses an unknown detector"
        assert _field(row, "behavior") in BEHAVIORS
        assert row.get("requires", DEFAULTS["requires"]) in REQUIRES
        # docs/01 §5: every trigger has a cooldown so she does not feel like a
        # keyword machine.
        cooldown = _field(row, "cooldown_turns")
        assert isinstance(cooldown, int) and cooldown >= 0
        assert 0 <= _field(row, "stage_min") <= _field(row, "stage_max") <= 5
        # `requires: all` means "every declared detector must agree"; with one
        # detector that is just `any` and would make the agreement rule dead.
        if row.get("requires") == "all":
            assert len(detect) >= 2, f"{trigger_id} requires agreement but has one detector"
        # The loader ignores an escalate key it does not know, so a typo would
        # silently fall back to the defaults.
        escalate = row.get("escalate", {})
        unknown = set(escalate) - {"axis", "max_steps", "step_scale"}
        assert not unknown, f"{trigger_id} has unknown escalate keys: {sorted(unknown)}"
        assert escalate.get("axis", DEFAULTS["escalate"]["axis"]) in ESCALATION_AXES


def test_keyword_patterns_and_model_labels_are_known() -> None:
    for trigger_id, row in TRIGGER_ROWS.items():
        keyword = row["detect"].get("keyword")
        if keyword is not None:
            patterns = (
                keyword
                if isinstance(keyword, list)
                else keyword.get("any", []) + keyword.get("all", [])
            )
            assert patterns, f"{trigger_id} declares a keyword detector with no pattern"
            for pattern in patterns:
                assert pattern.strip()
                re.compile(pattern)  # must be a usable expression
        for label in row["detect"].get("model", []):
            assert label in PROFILE_MAP["read_to_profile"], (
                f"{trigger_id} watches the read label {label!r}, "
                "which is not in docs/02 §1.2's enum"
            )


def test_event_rows_agree_with_the_telemetry_catalogue() -> None:
    event_rows = 0
    for trigger_id, row in TRIGGER_ROWS.items():
        for kind in row["detect"].get("event", []):
            event_rows += 1
            assert kind in TELEMETRY["events"], f"{trigger_id} watches unknown event {kind!r}"
            spec = TELEMETRY["events"][kind]
            assert spec["trigger"] == trigger_id, (
                f"{kind!r} is {spec['trigger']} in data/telemetry.json "
                f"but {trigger_id} in data/triggers.json"
            )
            # Telemetry gates the EVENT line, the trigger row gates her
            # reaction; the two docs/05 gates must be the same number.
            assert _field(row, "stage_min") == spec["stage_min"], (
                f"{trigger_id} stage gate disagrees with data/telemetry.json"
            )
    assert event_rows == len(TELEMETRY["events"]), "every engine event has a trigger row"


def test_e_rows_leave_the_line_to_telemetry() -> None:
    # data/telemetry.json already queues the docs/08 §6 EVENT line for an engine
    # event; a `line` here would ride the same prompt twice.
    for trigger_id, row in TRIGGER_ROWS.items():
        if "event" in row["detect"]:
            assert not row.get("line"), f"{trigger_id} would double telemetry's line"


def test_rows_match_the_bible_detection_column() -> None:
    for trigger_id, row in TRIGGER_ROWS.items():
        assert trigger_id in DOC_TRIGGERS, f"{trigger_id} is not a docs/01 §5 trigger"
        declared = {DETECTOR_LETTERS[detector] for detector in row["detect"]}
        assert declared <= DOC_TRIGGERS[trigger_id]["detect"], (
            f"{trigger_id} detects via {sorted(declared)} but docs/01 §5 says "
            f"{sorted(DOC_TRIGGERS[trigger_id]['detect'])}"
        )


def test_effects_use_the_game_vocabulary() -> None:
    for trigger_id, row in TRIGGER_ROWS.items():
        effects = row.get("effects", {})
        assert set(effects) <= {"meters", "profile", "path", "flags"}, trigger_id
        for meter, value in effects.get("meters", {}).items():
            assert meter in METER_NAMES, f"{trigger_id} moves unknown meter {meter!r}"
            assert isinstance(value, (int, float)) and value != 0
        for counter, value in effects.get("profile", {}).items():
            assert counter in PROFILE_COUNTERS, f"{trigger_id} bumps unknown counter {counter!r}"
            assert isinstance(value, int)
        for path, value in effects.get("path", {}).items():
            assert path in PATHS, f"{trigger_id} scores unknown path {path!r}"
            assert isinstance(value, int)
        for flag, value in effects.get("flags", {}).items():
            assert flag.strip()
            assert isinstance(value, (bool, int, float, str)), (
                f"{trigger_id} sets non-scalar flag {flag!r}"
            )


def test_escalating_rows_can_escalate() -> None:
    for trigger_id, row in TRIGGER_ROWS.items():
        if _field(row, "behavior") != "escalating":
            continue
        escalate = row.get("escalate", DEFAULTS["escalate"])
        assert escalate["max_steps"] >= 2, f"{trigger_id} escalates nowhere"
        assert escalate["step_scale"] > 0, f"{trigger_id} never grows"
        assert escalate.get("axis", DEFAULTS["escalate"]["axis"]) in ESCALATION_AXES


def test_stage_escalation_matches_the_bible() -> None:
    # docs/01 §5 T08 is the one trigger whose clause is "escalates with stage";
    # every such row must take the stage axis, and no other row may claim it by
    # accident (a stage axis ignores the firing count).
    for trigger_id, row in TRIGGER_ROWS.items():
        escalate = row.get("escalate", DEFAULTS["escalate"])
        axis = escalate.get("axis", DEFAULTS["escalate"]["axis"])
        says_stage = "escalates with stage" in DOC_TRIGGERS[trigger_id]["effect"]
        assert (axis == "stage") == says_stage, (
            f"{trigger_id} ships escalate.axis={axis!r} but docs/01 §5 says "
            f"{DOC_TRIGGERS[trigger_id]['effect']!r}"
        )
    assert TRIGGER_ROWS["T08"]["escalate"]["axis"] == "stage"


def test_line_templates_use_the_docs08_style() -> None:
    # A row's own line is a docs/08 §6 event line with the engine's tokens; a
    # typo in a token would reach the model verbatim.
    for trigger_id, row in TRIGGER_ROWS.items():
        lines = row.get("line", "")
        if isinstance(lines, str):
            lines = [lines] if lines else []
        for line in lines:
            assert line.startswith(("TRIGGER: ", "EVENT: ")), (
                f"{trigger_id} line is not a docs/08 §6 event line: {line!r}"
            )
            for token in re.findall(r"\{([a-z_]+)\}", line):
                assert token in LINE_TOKENS, f"{trigger_id} uses unknown token {{{token}}}"
