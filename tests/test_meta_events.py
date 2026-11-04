"""Data contract tests for game/data/meta_events.json (P3.08).

Guards the docs/05 §3 scheduling catalogue: every offered action needs a
docs/05 §2 OPPORTUNITY line and an offered_actions gate in stage_gates.json
(or it is silently unschedulable), and every catalogue row needs a note line
(docs/05 §2: she is told afterwards) plus a legal cap kind.

The last two tests are the docs/05 §0 hard rules that live in data: a row may
only write inside `user://` (rule 1) and may never carry a network, real-crash
or personal-file flag (rules 1–2), and every effect must name an accessibility
fallback (rule 5).
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META_EVENTS = json.loads(
    (ROOT / "game" / "data" / "meta_events.json").read_text(encoding="utf-8")
)
STAGE_GATES = json.loads(
    (ROOT / "game" / "data" / "stage_gates.json").read_text(encoding="utf-8")
)

REPEAT_KINDS = {"once_per_session", "once_per_save", "repeatable"}
PATHS = {"TSUN", "SPLIT", "YANDERE", "HOLLOW", "AWAKE", "ANCHOR"}

# docs/05 §3's per-path multipliers, transcribed: the doc's list is the
# authority for every row it names, and a row it does not name may carry no
# weight at all (P3.08 r1 CODE-3/DES-3: M22 was HOLLOW ×3 where the doc says
# YANDERE ×3, and M02 carried an undocumented AWAKE ×3).
PATH_WEIGHTS = {
    "M09": {"AWAKE": 3},
    "M10": {"AWAKE": 3},
    "M11": {"AWAKE": 3},
    "M12": {"AWAKE": 3},
    "M42": {"AWAKE": 3},
    "M25": {"HOLLOW": 3},
    "M30": {"HOLLOW": 3},
    "M21": {"YANDERE": 3},
    "M22": {"YANDERE": 3},
    "M23": {"YANDERE": 3},
    "M29": {"YANDERE": 3},
}

# docs/05 §0's effect classes, by catalogue id. `MetaDirector.ACTION_CLASS` is
# the runtime authority for rules 1 and 4; this mirror pins the data's own
# declarations to it, so a row cannot be gated above or below its class.
OS_DEEP = {"M13", "M14", "M15"}  # docs/05 §1.2 "Imm. ✔"
WRITE_EVENTS = {"M31"}  # docs/05 §1.4, the one offered file event

# The complete catalogue row vocabulary (docs/07 §2: the row is data, its shape
# is code). MetaDirector refuses a row with any other key, so the shipped data
# may only use these.
ROW_KEYS = {
    "meta",
    "stage",
    "repeat",
    "weights",
    "fallback",
    "note_line",
    "writes",
    "immersion_deep",
}


def _events() -> dict:
    return META_EVENTS["events"]


def _opportunities() -> dict:
    return STAGE_GATES["gates"]["opportunities"]


def _action_gates() -> dict:
    return STAGE_GATES["gates"]["offered_actions"]


def test_every_event_has_an_opportunity_line_and_gate() -> None:
    for action, spec in _events().items():
        line = _opportunities().get(action, "")
        assert line.startswith("OPPORTUNITY"), (
            f"{action}: docs/05 §2 offers need a data-authored reason "
            f"(stage_gates.gates.opportunities), got {line!r}"
        )
        gate = _action_gates().get(action)
        assert gate is not None, f"{action}: missing offered_actions gate"
        # The two gate copies must agree — one is the schema's, one the
        # scheduler's; a drift would offer an action the schema then rejects.
        assert gate == spec["stage"], (
            f"{action}: meta_events stage {spec['stage']} != "
            f"stage_gates gate {gate}"
        )


def test_every_event_has_a_note_line_and_legal_cap() -> None:
    for action, spec in _events().items():
        assert spec.get("meta"), f"{action}: missing docs/05 catalogue id"
        note = spec.get("note_line", "")
        assert note.startswith("EVENT:"), (
            f"{action}: docs/05 §2 needs a post-execution EVENT note, got {note!r}"
        )
        kind, cooldown = spec.get("repeat", [None, 0])
        assert kind in REPEAT_KINDS, f"{action}: bad repeat kind {kind!r}"
        assert isinstance(cooldown, int) and cooldown >= 0
        if kind != "repeatable":
            assert cooldown == 0, f"{action}: cooldown on a non-repeatable row"
        for path in spec.get("weights", {}):
            assert path in PATHS, f"{action}: unknown path weight {path!r}"


def test_path_weights_are_the_docs05_section_3_table() -> None:
    for action, spec in _events().items():
        expected = PATH_WEIGHTS.get(spec["meta"], {})
        assert spec.get("weights", {}) == expected, (
            f"{action} ({spec['meta']}): docs/05 §3 gives {expected}, row has "
            f"{spec.get('weights', {})} — a row carries only what its entry "
            f"documents"
        )


def test_row_keys_are_the_catalogue_vocabulary() -> None:
    # r1 SAF-2: rules 1–2 must not be opt-in. MetaDirector refuses a row with an
    # effect key it does not know, so the shipped data may only speak this
    # vocabulary — an unknown key here would be refused at runtime.
    for action, spec in _events().items():
        unknown = set(spec) - ROW_KEYS
        assert not unknown, f"{action}: unknown effect keys {sorted(unknown)}"


def test_hard_rule_4_declarations_match_the_os_class() -> None:
    # The gate derives rule 4 from `MetaDirector.ACTION_CLASS`; the row's
    # `immersion_deep` is documentation. Pin the two together so neither can
    # drift: every OS-level row declares it and no other row does.
    for action, spec in _events().items():
        is_deep = spec["meta"] in OS_DEEP
        assert bool(spec.get("immersion_deep", False)) == is_deep, (
            f"{action} ({spec['meta']}): immersion_deep must be {is_deep} — the "
            f"class is code, not the row's choice"
        )


def test_meta_floor_has_one_authority() -> None:
    # r1 CODE-5/DES-4: the scheduler's floor is the lowest row gate, so M31's
    # documented St 2 is reachable. The two duplicate copies are gone for good.
    gates = STAGE_GATES["gates"]
    assert "meta_min_stage" not in gates
    assert "scheduler_stage_min" not in META_EVENTS["rules"]
    assert min(spec["stage"] for spec in _events().values()) == 2  # M31, §1.4


def test_stage_gates_opportunities_only_cover_known_actions() -> None:
    known = set(_events()) | {"refuse_exit"}
    for action in _opportunities():
        assert action in known, (
            f"{action}: an OPPORTUNITY line for an action nothing can offer"
        )


def test_rules_block_is_the_docs05_shape() -> None:
    rules = META_EVENTS["rules"]
    assert rules["max_offers_per_turn"] == 2  # docs/02 §2.4: 0–2 actions
    assert rules["never_two_in_a_row"] is True  # docs/05 §3 hard rule
    caps = rules["per_scene_caps"]
    assert caps["3"] == 1 and caps["4"] == 2 and caps["5"] == 3
    # No second meta floor: the scheduler derives it from the row gates
    # (r1 CODE-5). An extra key here would be an ignored authority.
    assert set(rules) == {
        "max_offers_per_turn",
        "per_scene_caps",
        "default_scene_cap",
        "never_two_in_a_row",
    }


# docs/05 §0 rules 1–2: keys no catalogue row may ever carry. MetaDirector's
# `_hard_rule_violation()` refuses to offer a row that sets one; this keeps the
# shipped data on the right side of that gate.
FORBIDDEN_EFFECTS = (
    "network",
    "real_crash",
    "delete_files",
    "move_files",
    "read_personal_files",
)


def test_hard_rule_1_writes_stay_inside_user_dir() -> None:
    # r1 SAF-2: rule 1 is not opt-in — a write-class event must DECLARE its
    # target; deleting `writes` from M31 must not make the row legal.
    for action, spec in _events().items():
        for key in FORBIDDEN_EFFECTS:
            assert not spec.get(key), f"{action}: docs/05 §0 forbids {key!r}"
        target = spec.get("writes", "")
        if spec["meta"] in WRITE_EVENTS:
            assert isinstance(target, str) and target.strip(), (
                f"{action}: a write event must declare `writes` inside user://"
            )
        if not target:
            continue
        assert target.startswith("user://"), (
            f"{action}: docs/05 §0 rule 1 — {target!r} is outside user://"
        )
        assert ".." not in target.replace("\\", "/").split("/"), (
            f"{action}: docs/05 §0 rule 1 — {target!r} climbs out of user://"
        )


def test_hard_rule_5_every_event_names_an_accessibility_fallback() -> None:
    for action, spec in _events().items():
        fallback = spec.get("fallback")
        assert isinstance(fallback, str) and fallback.strip(), (
            f"{action}: docs/05 §0 rule 5 needs the in-window / reduced-motion "
            "fallback so a player without the effect still gets the beat"
        )
