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
    "flag_set",
    "flag_absent",
}
GUARD_KEYS = GUARD_CLOCK_KEYS | {"counter_gte", "contradicts_memory"}
DETECTOR_LETTERS = {"keyword": "K", "model": "M", "event": "E", "clock": "C"}
LINE_TOKENS = {"count", "ordinal", "stage", "day", "turn", "fact"}
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
    "first_effects",
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
        # `effects` lands on every firing, `first_effects` only on the first
        # (P2.22B) — both are the same effect vocabulary.
        for group_key in ("effects", "first_effects"):
            effects = row.get(group_key, {})
            assert set(effects) <= {"meters", "profile", "path", "flags"}, trigger_id
            for meter, value in effects.get("meters", {}).items():
                assert meter in METER_NAMES, f"{trigger_id} moves unknown meter {meter!r}"
                assert isinstance(value, (int, float)) and value != 0
            for counter, value in effects.get("profile", {}).items():
                assert counter in PROFILE_COUNTERS, (
                    f"{trigger_id} bumps unknown counter {counter!r}"
                )
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


def test_t01_t15_rows_are_the_shipped_catalogue() -> None:
    # P2.10's whole acceptance criterion in one place: all fifteen exist, by id.
    covered = {f"T{n:02d}" for n in range(1, 16)}
    assert covered <= set(TRIGGER_ROWS), "P2.10 ships T01–T15"
    for trigger_id in sorted(covered):
        row = TRIGGER_ROWS[trigger_id]
        assert row["name"].strip(), f"{trigger_id} has no name"
        assert row["detect"] or row.get("guard"), f"{trigger_id} has no evidence"


def test_documented_effects_land() -> None:
    # docs/01 §5's numbers are the acceptance criterion, so the ones the bible
    # states are pinned exactly; the unnumbered rows only have to point the way
    # the clause points.
    assert TRIGGER_ROWS["T01"]["first_effects"]["meters"]["instability"] == 8
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


def test_t01_spikes_once_and_asks_again() -> None:
    """P2.22B retune (handoff DCR-2): T01 is agreement-only and its +8 lands once.

    The live P2.22 run fired T01 19 times in 84 turns (16 of them model-only on
    possessive lines that mention no girl) for 88 of the 130.7 Instability the
    campaign had — Terminal on day 5. docs/01 §5's row gives the +8 for a
    mention, and 'again each time you bring her up' is the question repeating,
    so the spike sits in first_effects while the path points and the line keep
    landing. The 3-turn cooldown is docs/01 §5's 'cooldown so she doesn't feel
    like a keyword machine' (16 turns was the observed spacing at the model's
    over-labelling rate).
    """
    row = TRIGGER_ROWS["T01"]
    assert row["requires"] == "all", "a model-only read is an intent, not a mention"
    assert set(row["detect"]) == {"keyword", "model"}
    assert row["cooldown_turns"] == 3
    assert row["behavior"] == "repeatable"
    assert set(row["first_effects"]["meters"]) == {"instability"}
    assert set(row["effects"]) == {"path"}
    assert "instability" not in row["effects"].get("meters", {})
    # The spike is the only first_effects in the catalogue: a second one would
    # mean a row whose doc effect is silently capped without its own DCR.
    users = [
        trigger_id
        for trigger_id, other in TRIGGER_ROWS.items()
        if other.get("first_effects", {}).get("meters")
        or other.get("first_effects", {}).get("path")
        or other.get("first_effects", {}).get("profile")
    ]
    assert users == ["T01"]


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
