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
    for action, spec in _events().items():
        for key in FORBIDDEN_EFFECTS:
            assert not spec.get(key), f"{action}: docs/05 §0 forbids {key!r}"
        if "writes" not in spec:
            continue
        target = spec["writes"]
        assert target.startswith("user://"), (
            f"{action}: docs/05 §0 rule 1 — {target!r} is outside user://"
        )
        assert ".." not in target.replace("\\", "/").split("/"), (
            f"{action}: docs/05 §0 rule 1 — {target!r} climbs out of user://"
        )


def test_hard_rule_5_every_event_names_an_accessibility_fallback() -> None:
    for action, spec in _events().items():
        fallback = spec.get("fallback", "").strip()
        assert fallback, (
            f"{action}: docs/05 §0 rule 5 needs the in-window / reduced-motion "
            "fallback so a player without the effect still gets the beat"
        )
