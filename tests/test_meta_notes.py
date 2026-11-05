"""Data contract for docs/05 §1.4–§1.5 (P3.11): game/data/meta_notes.json.

The file is content — every string, tint and template — but its *shape* and the
stage gates are docs/05, and the module's file paths must stay under `user://`
(docs/05 §0 rule 1). A data edit that breaks either is a red suite here rather
than a quiet behaviour change at runtime.

Gates are the docs table itself:

    M31 letter        St 2          M35 clock          any
    M32 diary         St 3          M36 3 AM           St 1
    M33 save names    St 4          M37 birthday       any
    M34 other player  St 4 / AWAKE  M38 long session   St 2
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game" / "data" / "meta_notes.json"
CATALOGUE = ROOT / "game" / "data" / "meta_events.json"

DOCS_GATES = {
    "letter": 2,
    "diary": 3,
    "slot_names": 4,
    "other_player": 4,
    "clock": 0,
    "three_am": 1,
    "birthday": 0,
    "long_session": 2,
}

# Which placeholders each EVENT line must carry so String.format() can never
# fail at runtime (a missing key is an error in Godot, not a blank).
NOTE_SLOTS = {
    "three_am": {"clock", "line"},
    "birthday": {"month_name", "day", "line"},
    "long_session": {"hours", "line"},
    "slot_names": {"name", "slot"},
    "other_player": {"name"},
    "diary": {"day"},
}


def _data() -> dict:
    return json.loads(DATA.read_text(encoding="utf-8"))


def test_file_is_the_documented_top_level_shape() -> None:
    data = _data()
    assert data["version"] == 1
    assert "docs/05" in data["doc"]
    for section in (
        "paths",
        "gates",
        "time",
        "three_am",
        "birthday",
        "long_session",
        "letter",
        "diary",
        "slot_names",
        "other_player",
        "ui",
    ):
        assert section in data, section


def test_stage_gates_are_the_docs_table() -> None:
    assert _data()["gates"] == DOCS_GATES


def test_every_path_is_relative_and_cannot_climb() -> None:
    paths = _data()["paths"]
    for name, value in paths.items():
        assert isinstance(value, str) and value
        assert not value.startswith("/"), name
        assert ".." not in value, name
        assert ":" not in value, name
        assert "\\" not in value, name


def test_letters_target_matches_the_offered_rows_declared_write() -> None:
    # M31 is an OFFERED action, so its `writes` in meta_events.json is what
    # docs/05 §0 rule 1's gate reads. The module's own letters folder must be
    # the same target, or the declaration would be a lie.
    letters = _data()["paths"]["letters"]
    row = json.loads(CATALOGUE.read_text(encoding="utf-8"))["events"]["write_note"]
    assert row["meta"] == "M31"
    assert row["writes"] == f"user://{letters}/"


def test_file_templates_are_printf_shapes() -> None:
    data = _data()
    assert data["letter"]["file_format"].count("%") == 1
    assert data["letter"]["file_format"].endswith(".txt")
    assert "s" in data["letter"]["file_format"]
    assert data["diary"]["file_format"].count("%") == 1
    assert "%02d" in data["diary"]["file_format"]
    assert data["letter"]["slug_max"] > 0
    assert data["letter"]["slug_fallback"].isalnum()


def test_every_event_line_is_an_event_line_with_its_placeholders() -> None:
    data = _data()
    notes = {
        "three_am": data["three_am"]["note"],
        "birthday": data["birthday"]["note"],
        "long_session": data["long_session"]["note"],
        "slot_names": data["slot_names"]["note"],
        "other_player": data["other_player"]["note"],
        "diary": data["diary"]["note"],
    }
    for name, note in notes.items():
        assert note.startswith("EVENT: "), name
        placeholders = set(re.findall(r"\{(\w+)\}", note))
        assert NOTE_SLOTS[name] <= placeholders, name
    greeting = data["time"]["greeting_note"]
    assert greeting.startswith("EVENT: ")
    assert {"clock", "label"} <= set(re.findall(r"\{(\w+)\}", greeting))


def test_the_clock_buckets_cover_every_hour_exactly_once() -> None:
    buckets = _data()["time"]["buckets"]
    seen = []
    for bucket in buckets:
        assert 0 <= bucket["from"] <= bucket["to"] <= 23
        assert 0.0 <= bucket["tint_strength"] <= 1.0
        assert re.fullmatch(r"#[0-9a-fA-F]{6}", bucket["tint"])
        seen.extend(range(bucket["from"], bucket["to"] + 1))
    assert sorted(seen) == list(range(24))
    assert len(seen) == len(set(seen))


def test_three_am_is_the_documented_band_and_price() -> None:
    three_am = _data()["three_am"]
    assert (three_am["from"], three_am["to"]) == (2, 4)
    assert three_am["instability"] == 3.0
    assert three_am["music"] == "music_box"
    assert set(three_am["lines"]) >= {"0", "1", "2", "3", "4", "5"}


def test_birthday_months_and_patterns_are_usable() -> None:
    birthday = _data()["birthday"]
    assert sorted(birthday["months"].values()) == list(range(1, 13))
    assert len(birthday["month_names"]) == 12
    assert birthday["keywords"]
    orders = set()
    for pattern in birthday["patterns"]:
        assert pattern["order"] in {"dmy", "mdy", "iso"}
        re.compile(pattern["regex"])
        orders.add(pattern["order"])
    assert orders == {"dmy", "mdy", "iso"}


def test_long_session_is_two_hours() -> None:
    assert _data()["long_session"]["seconds"] == 7200
    assert "ANCHOR" in _data()["long_session"]["path_lines"]


def test_ui_strings_are_non_empty() -> None:
    for key, value in _data()["ui"].items():
        assert isinstance(value, str) and value.strip(), key


def test_notes_never_name_a_real_condition() -> None:
    # docs/01 §4 sensitivity rule / docs/02 §8: no real disorder is ever named
    # in game text, including the files she leaves.
    banned = [
        "schizophren",
        "psychosis",
        "bipolar",
        "borderline personality",
        "ptsd",
        "dissociative identity",
        "sociopath",
        "psychopath",
    ]
    blob = json.dumps(_data(), ensure_ascii=False).lower()
    for term in banned:
        assert term not in blob, term
