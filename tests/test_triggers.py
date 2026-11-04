"""P2.08 + P2.10 — pin the docs/01 §5 trigger catalogue the engine reads.

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
PATHS_DATA = json.loads((ROOT / "game" / "data" / "paths.json").read_text(encoding="utf-8"))
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
# docs/01 §4: the six path formulas read three counters of their own beside the
# twelve §2 tags. data/paths.json is the only list — GameState's
# `Paths.counters()` reads the same terms, so P2.12's seam and this contract
# cannot drift — so the set is derived instead of restated.
FORMULA_COUNTERS = {
    term["counter"]
    for terms in PATHS_DATA["scores"].values()
    for term in terms
    if "counter" in term
}
PROFILE_COUNTERS = PROFILE_COUNTERS | FORMULA_COUNTERS
# TriggerEngine's vocabulary.
BEHAVIORS = {"once", "repeatable", "escalating"}
REQUIRES = {"any", "all"}
ESCALATION_AXES = {"step", "stage"}
DETECTORS = {"keyword", "model", "event", "clock"}
# TriggerEngine's guard vocabulary (P2.10): a guard holds a condition that must
# also be true but that is not a detection letter (see the row-field contract).
GUARD_CLOCK_KEYS = {
    "day_gte",
    "day_lte",
    "day_eq",
    "turn_gte",
    "hour_from",
    "hour_to",
    "absence_hours_gte",
    "absence_hours_lte",
    "absence_hours_lt",
    "flag_set",
    "flag_absent",
}
# `absence_hours_lt` is the one P3.07 actually shipped (T17's strict 168 h
# reunion bound); `absence_hours_lte` is part of the engine's vocabulary but no
# row uses it, so both stay in the list the loader accepts.
GUARD_KEYS = GUARD_CLOCK_KEYS | {
    "counter_gte",
    "contradicts_memory",
    "mentions_memory",
    "name_mention",
    "text_match",
}
DETECTOR_LETTERS = {"keyword": "K", "model": "M", "event": "E", "clock": "C"}
LINE_TOKENS = {"count", "ordinal", "stage", "day", "turn", "fact", "name"}
GUARD_ROW_KEYS = {
    "contradicts_memory": {"negations", "min_shared_words"},
    "mentions_memory": {"min_shared_words"},
    "name_mention": {"pattern", "exclude", "ignore_case"},
    "text_match": {"any", "all", "ignore_case"},
}
# The row fields the loader reads. A misspelt field would be dropped silently,
# so an unknown key is a contract failure, not data (P2.10 r2 CODE-5).
ROW_KEYS = {
    "name",
    "detect",
    "observe",
    "guard",
    "requires",
    "behavior",
    "escalate",
    "cooldown_turns",
    "stage_min",
    "stage_max",
    "effects",
    "line",
}

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
        guard = row.get("guard", {})
        assert isinstance(detect, dict), f"{trigger_id} detect is not an object"
        assert isinstance(guard, dict), f"{trigger_id} guard is not an object"
        # Evidence is a detector or a guard the game evaluates itself (T13/T15:
        # docs/02 §1.2's read enum has no label for a lie or an ignored question).
        assert detect or guard, f"{trigger_id} has neither a detector nor a guard"
        assert set(row) <= ROW_KEYS, (
            f"{trigger_id} has unknown fields: {sorted(set(row) - ROW_KEYS)}"
        )
        assert set(detect) <= DETECTORS, f"{trigger_id} uses an unknown detector"
        observe = row.get("observe", {})
        assert isinstance(observe, dict), f"{trigger_id} observe is not an object"
        for flag, value in observe.items():
            assert isinstance(flag, str) and flag.strip(), f"{trigger_id} has an empty flag"
            assert isinstance(value, (bool, int, float, str)), (
                f"{trigger_id} observe flag {flag!r} is not a scalar"
            )
        assert set(guard) <= GUARD_KEYS, f"{trigger_id} uses an unknown guard: {sorted(guard)}"
        for counter, floor in guard.get("counter_gte", {}).items():
            assert counter in PROFILE_COUNTERS, f"{trigger_id} guards unknown counter {counter!r}"
            assert isinstance(floor, int) and floor > 0, f"{trigger_id} counter floor is not a count"
        contradiction = guard.get("contradicts_memory")
        if contradiction is not None:
            assert isinstance(contradiction, dict), f"{trigger_id} contradiction is not an object"
            for cue in contradiction.get("negations", ["never"]):
                assert isinstance(cue, str) and cue.strip(), f"{trigger_id} has an empty cue"
            if "min_shared_words" in contradiction:
                shared = contradiction["min_shared_words"]
                assert isinstance(shared, int) and shared > 0 
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
            # reaction; the two docs/05 gates must be the same number. A gate
            # no doc states is absent on both sides (T20/T21, DES-1/D20).
            assert _field(row, "stage_min") == spec.get("stage_min", 0), (
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


def test_new_guard_blocks_are_well_formed() -> None:
    # P3.07 guards: mentions_memory (T22) and name_mention (T26) get the same
    # sub-key discipline the contradicts_memory block already has — a typo'd
    # key must fail here, not drop silently.
    for trigger_id, row in TRIGGER_ROWS.items():
        guard = row.get("guard", {})
        assert set(guard) <= GUARD_KEYS, f"{trigger_id} uses unknown guard keys {set(guard) - GUARD_KEYS}"
        for key, allowed in GUARD_ROW_KEYS.items():
            if key in guard:
                assert set(guard[key]) <= allowed, (
                    f"{trigger_id} guard.{key} has unknown keys {set(guard[key]) - allowed}"
                )
    mention = TRIGGER_ROWS["T22"]["guard"]["mentions_memory"]
    assert mention["min_shared_words"] >= 2, "a gift is not remembered on one shared word"
    naming = TRIGGER_ROWS["T26"]["guard"]["name_mention"]
    assert re.search(naming["pattern"], "my name is Ren").group(1) == "Ren"
    for bad in (
        "call me Leila",
        "call me baby",
        "call me later",
        "call me when you get home",
        # CODE-4: the capture must not take a function word for a name, or the
        # `once` row renames the player "Not" for the rest of the save.
        "my name is not important",
        "my name is just a name",
        "my name is still a secret",
        "my name is really boring",
        "my name is only for friends",
    ):
        match = re.search(naming["pattern"], bad, re.I)
        assert match.group(1).lower() in naming["exclude"], f"{bad!r} must be excluded"
    # T23/T28/T30's text guard is a keyword-shaped matcher: every branch must
    # compile, and the documented examples must take it.
    for trigger_id, sample in (
        ("T23", "you look so pretty tonight"),
        ("T28", "thank you for tonight"),
        ("T30", "your mother, what was she like?"),
    ):
        spec = TRIGGER_ROWS[trigger_id]["guard"]["text_match"]
        patterns = spec.get("any", []) + spec.get("all", [])
        assert patterns, f"{trigger_id} text_match has no pattern"
        for pattern in patterns:
            re.compile(pattern)
        assert any(re.search(p, sample, re.I if spec.get("ignore_case", True) else 0) for p in patterns), (
            f"{trigger_id} text_match misses {sample!r}"
        )


def test_t23_appearance_guard_keeps_a_compliment_honest() -> None:
    # DES-2: docs/01 §5 T23 is "Compliment her appearance only", but the bare
    # `compliment` read label also covers "you're so smart". The guard is a
    # precondition on the message (never a detection letter), so the row stays
    # an M row while a non-appearance compliment no longer earns an accusation.
    spec = TRIGGER_ROWS["T23"]["guard"]["text_match"]
    patterns = spec.get("any", []) + spec.get("all", [])
    assert patterns, "T23 needs an appearance precondition"

    def fires(text: str) -> bool:
        return any(re.search(p, text, re.I if spec.get("ignore_case", True) else 0) for p in patterns)

    for appearance in (
        "you're so pretty",
        "you look beautiful tonight",
        "your eyes are gorgeous",
        "I love your hair",
        "you have such a nice smile",
    ):
        assert fires(appearance), f"T23 misses {appearance!r}"
    for other in (
        "you're so smart",
        "you are so kind",
        "you're a good listener",
        "you're funny",
        # T24's symptom report is not a compliment: the guard must not claim it.
        "your eyes look wrong",
        "your smile looks strange",
    ):
        assert not fires(other), f"T23 fires on {other!r}"
    assert set(TRIGGER_ROWS["T23"]["detect"]) == {"model"}, "the guard adds no detection letter"


def test_accessibility_accommodations_are_never_triggers() -> None:
    # D20 (DECISIONS.md, hard rule): accessibility and safety accommodations must
    # never be narratively punished — no trigger, no meta event, no path weight.
    # Settings.is_accommodation() is the one classifier; this pins the policy
    # list so a future setter cannot quietly emit settings_changed for one.
    settings = (ROOT / "game" / "autoload" / "Settings.gd").read_text(encoding="utf-8")
    listed = re.search(r"ACCOMMODATION_KEYS: Array\[String\] = \[([^\]]+)\]", settings)
    assert listed, "Settings must keep the D20 accommodation list"
    keys = {item.strip().strip('"') for item in listed.group(1).split(",") if item.strip()}
    assert {"photosensitive", "reduced_motion", "text_speed", "volume"} <= keys
    # The calmer content ceiling is the accommodation; the full ceiling is a
    # preference and may still reach T20.
    assert "_heal_content_level(value) == CALMER_CONTENT" in settings
    # No trigger row may watch an accommodation key by name.
    for trigger_id, row in TRIGGER_ROWS.items():
        for key in keys:
            assert key not in json.dumps(row), f"{trigger_id} reacts to the {key!r} accommodation"
    # T20's only detector is the preference event, and T21 owns the mute pair:
    # an accommodation write can therefore never reach another row.
    assert TRIGGER_ROWS["T20"]["detect"] == {"event": ["settings_changed"]}
    assert TELEMETRY["events"]["settings_changed"]["trigger"] == "T20"


def test_t19_run_end_carries_the_ended_stage() -> None:
    # CODE-2/D19: a New Game has reset GameState before she may speak, so the
    # rows that are about the previous run must be gated on the stage the EVENT
    # names. The data side of that contract is one documented key.
    doc = TRIGGERS["doc"]
    assert "gate_stage" in doc, "the row vocabulary must document gate_stage"
    assert "gate_stage" in TELEMETRY["_doc"], "the event catalogue must document gate_stage"
    telegraph = (ROOT / "game" / "autoload" / "Telemetry.gd").read_text(encoding="utf-8")
    assert 'data.get("gate_stage", -1)' in telegraph or "data.get(\"gate_stage\"" in telegraph
    assert "_deliver_run_ended" in telegraph and "_run_ended" in telegraph


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
            # P3.07 T21 "until unmuted": an event row's flag may follow the
            # event's own data instead of a constant — {"from_event": "muted"}
            # is mute -> true / unmute -> false, one row for the whole span.
            if isinstance(value, dict):
                assert set(value) == {"from_event"}, (
                    f"{trigger_id} flag {flag!r} has unknown keys {sorted(value)}"
                )
                assert isinstance(value["from_event"], str) and value["from_event"].strip()
                continue
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


def test_t01_t15_rows_are_the_shipped_catalogue() -> None:
    # P2.10's whole acceptance criterion in one place: all fifteen exist, by id.
    covered = {f"T{n:02d}" for n in range(1, 16)}
    assert covered <= set(TRIGGER_ROWS), "P2.10 ships T01–T15"
    for trigger_id in sorted(covered):
        row = TRIGGER_ROWS[trigger_id]
        assert row["name"].strip(), f"{trigger_id} has no name"
        assert row["detect"] or row.get("guard"), f"{trigger_id} has no evidence"


def test_t16_t32_rows_are_the_shipped_catalogue() -> None:
    # P3.07's whole acceptance criterion in one place: all seventeen exist.
    covered = {f"T{n:02d}" for n in range(16, 33)}
    assert covered <= set(TRIGGER_ROWS), "P3.07 ships T16–T32"
    for trigger_id in sorted(covered):
        row = TRIGGER_ROWS[trigger_id]
        assert row["name"].strip(), f"{trigger_id} has no name"
        assert row["detect"] or row.get("guard"), f"{trigger_id} has no evidence"


def test_documented_effects_land() -> None:
    # docs/01 §5's numbers are the acceptance criterion, so the ones the bible
    # states are pinned exactly; the unnumbered rows only have to point the way
    # the clause points.
    assert TRIGGER_ROWS["T01"]["effects"]["meters"]["instability"] == 8
    assert TRIGGER_ROWS["T01"]["effects"]["path"]["YANDERE"] == 3
    assert TRIGGER_ROWS["T03"]["effects"]["meters"]["instability"] == 5
    assert TRIGGER_ROWS["T03"]["effects"]["meters"]["affection"] > 0
    assert TRIGGER_ROWS["T04"]["effects"]["path"]["SPLIT"] == 5
    assert TRIGGER_ROWS["T05"]["effects"]["path"]["AWAKE"] == 4
    assert TRIGGER_ROWS["T06"]["effects"]["path"]["AWAKE"] == 6
    assert TRIGGER_ROWS["T07"]["effects"]["path"]["AWAKE"] == 10
    assert TRIGGER_ROWS["T13"]["effects"]["meters"]["trust"] == -10
    contradiction = TRIGGER_ROWS["T13"]["guard"]["contradicts_memory"]
    assert contradiction["min_shared_words"] >= 2, "one shared word is a coincidence"
    for plain in ("never", "don't", "do not", "didn't", "wasn't", "was not"):
        assert plain not in contradiction["negations"], (
            f"{plain!r} is ordinary negation, not a denial of a statement"
        )
    for trigger_id, path_id in [
        ("T02", "SPLIT"),
        ("T02", "YANDERE"),
        ("T11", "HOLLOW"),
        ("T14", "TSUN"),
        ("T14", "SPLIT"),
        ("T15", "HOLLOW"),
        ("T15", "SPLIT"),
    ]:
        points = TRIGGER_ROWS[trigger_id]["effects"]["path"][path_id]
        assert points > 0, f"{trigger_id} does not spike {path_id}"
    # Docs/01 §5 T06/T14's "sprite 29 / sprite 17 flash" is a flag: the effects
    # vocabulary is meters/profile/path/flags (P2.08's row shape).
    assert TRIGGER_ROWS["T06"]["effects"]["flags"]["flash_sprite"] == 29
    assert TRIGGER_ROWS["T14"]["effects"]["flags"]["flash_sprite"] == 17
    # docs/01 §5 T09/T12's numbers (r2 DES-3: the bible states them now).
    assert TRIGGER_ROWS["T09"]["effects"]["path"]["SPLIT"] == 2
    assert TRIGGER_ROWS["T12"]["effects"]["profile"]["apathy"] == 1
    assert "SPLIT +2" in DOC_TRIGGERS["T09"]["effect"]
    assert "apathy +1" in DOC_TRIGGERS["T12"]["effect"]
    assert "again each time you bring her up" in DOC_TRIGGERS["T01"]["effect"]
    # P2.12's seam: the two §4 formula counters the brief names are fed here.
    assert "broken_promises" in TRIGGER_ROWS["T13"]["effects"]["profile"]
    assert TRIGGER_ROWS["T15"]["guard"]["counter_gte"] == {"ignored_questions": 1}
    # docs/01 §5 T16/T18's stated numbers (P3.07): the night window is 2–4 AM
    # with Instability +3, and the 7-day return is the big spike.
    assert TRIGGER_ROWS["T16"]["effects"]["meters"]["instability"] == 3
    assert TRIGGER_ROWS["T16"]["detect"]["clock"] == {"hour_from": 2, "hour_to": 4}
    assert TRIGGER_ROWS["T17"]["detect"]["clock"]["absence_hours_gte"] == 24
    assert TRIGGER_ROWS["T18"]["detect"]["clock"]["absence_hours_gte"] == 168
    assert TRIGGER_ROWS["T18"]["effects"]["meters"]["instability"] > 3
    # T26's name is confirmed ONCE and then persists through the save shadow.
    # CODE-3: the flag means "this row fired", so it is an effect — `observe`
    # runs on the read label alone and would set it on any greeting.
    assert TRIGGER_ROWS["T26"]["behavior"] == "once"
    assert TRIGGER_ROWS["T26"]["effects"]["flags"]["name_confirmed"] is True
    assert "observe" not in TRIGGER_ROWS["T26"], "a read label is not a confirmation"
    # T17's reunion window ends where T18's 7 days begin, and 168 h belongs to
    # the week row alone (strict upper bound on the day row).
    assert TRIGGER_ROWS["T17"]["detect"]["clock"]["absence_hours_lt"] == 168
    assert "absence_hours_lt" not in TRIGGER_ROWS["T18"]["detect"]["clock"]
    # T19 "Stage 3+ only" is the row's gate, and the telemetry line's gate.
    assert TRIGGER_ROWS["T19"]["stage_min"] == 3
    assert TELEMETRY["events"]["save_gone"]["stage_min"] == 3
    # DES-1/D20: no doc states a stage gate for T20/T21, so the invented
    # `stage_min: 1` is gone from both the rows and their EVENT lines.
    for trigger_id, kinds in (
        ("T20", ["settings_changed"]),
        ("T21", ["audio_mute", "audio_unmuted"]),
    ):
        assert "stage_min" not in TRIGGER_ROWS[trigger_id], f"{trigger_id} has an invented gate"
        for kind in kinds:
            assert "stage_min" not in TELEMETRY["events"][kind], f"{kind} has an invented gate"
    # T21 "until unmuted": the ALL-CAPS flag follows the event's own data.
    assert TRIGGER_ROWS["T21"]["effects"]["flags"]["audio_muted"] == {"from_event": "muted"}
    assert set(TRIGGER_ROWS["T21"]["detect"]["event"]) == {"audio_mute", "audio_unmuted"}


def test_t03_t04_are_one_clock_pair() -> None:
    # docs/01 §5 T03 "before Day 3" is a clock GUARD (the row stays a K row, so
    # the reaction rides the turn the player speaks), and T04 is the C row. The
    # flag T03 writes is what makes T04's clock detector stand down.
    t03 = TRIGGER_ROWS["T03"]
    assert t03["guard"]["day_lte"] == 2
    # The flag is written by `observe`, which runs before the guard: ANY
    # confession sets it, so a Day 3–9 confession stands T04 down (r2 CODE-1).
    assert t03["observe"]["love_confessed"] is True
    assert "flags" not in t03["effects"], "the reaction must not be the flag's only writer"
    t04 = TRIGGER_ROWS["T04"]
    assert t04["detect"]["clock"]["day_gte"] == 10
    assert t04["detect"]["clock"]["flag_absent"] == "love_confessed"
    assert t04["behavior"] == "once"


def test_guard_only_rows_are_the_game_checks() -> None:
    # T13/T15 are M in docs/01 §5, but docs/02 §1.2's 17 read labels cannot say
    # "that was a lie" or "you ignored my question", so the game decides and the
    # row declares no detector at all (P2.10 handoff DCR-1/DCR-2). A guard-only
    # row fires at full strength — its evidence is not a guess.
    t13, t15 = TRIGGER_ROWS["T13"], TRIGGER_ROWS["T15"]
    assert t13["detect"] == {}
    assert "contradicts_memory" in t13["guard"]
    assert t15["detect"] == {}
    assert t15["guard"] == {"counter_gte": {"ignored_questions": 1}}
    # Nothing about them may claim a detection letter the bible did not give.
    for trigger_id in ("T13", "T15"):
        declared = {DETECTOR_LETTERS[detector] for detector in TRIGGER_ROWS[trigger_id]["detect"]}
        assert declared == set()


def test_t01_name_list_has_no_common_nouns() -> None:
    # r2 CODE-4: "she moved with such grace" is not another girl. Every name
    # alternative must fail on a sentence that only uses the word as a noun.
    names = TRIGGER_ROWS["T01"]["detect"]["keyword"]["any"][0]
    assert not re.search(names, "she moved with such grace through the room", re.I)
    assert re.search(names, "I ran into Sarah on the way here", re.I)


def test_t02_see_you_is_a_farewell_not_a_greeting() -> None:
    # r2 CODE-2: "I see you, Leila" is a date line. The row keeps the farewell.
    patterns = TRIGGER_ROWS["T02"]["detect"]["keyword"]["any"]

    def fires(text: str) -> bool:
        return any(re.search(pattern, text, re.I) for pattern in patterns)

    assert fires("see you later")
    assert fires("I have to go now")
    assert not fires("I see you, Leila. You look tired.")
