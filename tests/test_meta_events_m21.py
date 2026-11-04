"""Data contract tests for game/data/meta_events_m21.json (P3.10).

The docs/05 §1.3 M21–M26 content table, guarded the same way P3.08 guards the
offer catalogue: every scripted row must carry the doc's stage gate, a path
condition that names real paths, an authored EVENT note (docs/05 §2), and a
per-turn chance that cannot be 1.0 — "rare, earned" is the pillar, so a data
edit cannot make an event fire every turn.

The last tests are the safety rules this range could break from data alone:

* docs/05 §0 rule 1 — nothing here names a file or a write target;
* docs/05 §0 rule 2 — nothing here names a network call or a real crash;
* D20 + docs/05 §0 rule 5 — M26's sabotage names an audio bus and a display
  offset only. No accessibility value (photosensitive, reduced motion, calmer,
  text speed, the mix itself) can be touched by a meta event, so the row may not
  even mention them.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads(
    (ROOT / "game" / "data" / "meta_events_m21.json").read_text(encoding="utf-8")
)
META_EVENTS = json.loads(
    (ROOT / "game" / "data" / "meta_events.json").read_text(encoding="utf-8")
)

PATHS = {"TSUN", "SPLIT", "YANDERE", "HOLLOW", "AWAKE", "ANCHOR"}
SCRIPTED = ("m23", "m24", "m26")

# docs/05 §1.3, transcribed: the gate each row must carry.
DOC_STAGE = {"m23": 4, "m24": 4, "m26": 3}
# The doc's "/ SPLIT, YANDERE" style path conditions.
DOC_PATHS = {"m23": {"SPLIT", "YANDERE"}, "m24": {"SPLIT"}, "m26": set()}
# docs/05 §0 rule 1 / rule 2 names this range may not contain.
FORBIDDEN_KEYS = {"network", "real_crash", "delete_files", "move_files", "read_personal_files"}
# D20: accessibility and safety accommodations are never an event's target.
ACCESSIBILITY_KEYS = {
    "photosensitive",
    "reduced_motion",
    "calmer",
    "content_level",
    "text_speed",
    "volume",
    "bus_volumes",
}


def _row(key: str) -> dict:
    return DATA[key]


def _walk(value):
    """Yield every (key, value) pair in the document, nested ones included."""
    if isinstance(value, dict):
        for key, inner in value.items():
            yield key, inner
            yield from _walk(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from _walk(inner)


def test_document_is_a_versioned_json_object() -> None:
    assert isinstance(DATA, dict)
    assert DATA["version"] == 1
    assert isinstance(DATA["_doc"], str) and DATA["_doc"].strip()
    for key in SCRIPTED:
        assert isinstance(DATA[key], dict), key


def test_scripted_rows_carry_the_docs_stage_and_path_condition() -> None:
    for key in SCRIPTED:
        row = _row(key)
        assert row["stage"] == DOC_STAGE[key], key
        assert set(row.get("paths", [])) == DOC_PATHS[key], key
        assert set(row.get("paths", [])) <= PATHS, key


def test_every_scripted_row_is_rare_and_tunable() -> None:
    for key in SCRIPTED:
        chance = _row(key)["chance"]
        assert isinstance(chance, float) or isinstance(chance, int), key
        assert 0.0 < chance < 1.0, f"{key}: docs/05 §3 'rare, earned' — no guaranteed row"


def test_every_scripted_row_tells_her_afterwards() -> None:
    for key in SCRIPTED:
        note = _row(key)["note_line"]
        assert isinstance(note, str) and note.strip(), key
        assert note.startswith("EVENT:"), f"{key}: docs/05 §2 note line"


def test_no_row_names_a_forbidden_effect_or_a_file() -> None:
    for key, value in _walk(DATA):
        assert key not in FORBIDDEN_KEYS, key
        assert key not in ACCESSIBILITY_KEYS, key
    text = json.dumps(DATA, ensure_ascii=False)
    assert "res://" not in text
    assert "user://" not in text
    assert "/home/" not in text


def test_m23_swaps_are_plain_game_authored_pairs() -> None:
    swaps = _row("m23")["swaps"]
    assert swaps, "M23 needs at least one word rule"
    for pair in swaps:
        assert isinstance(pair, list) and len(pair) == 2
        assert all(isinstance(word, str) and word.strip() for word in pair)
        assert all("{" not in word and "}" not in word for word in pair)
        assert pair[0] != pair[1]
    prefix = _row("m23")["prefix"]
    assert isinstance(prefix, str) and prefix.strip()
    assert "{" not in prefix


def test_m24_rewrites_both_speakers_within_a_window() -> None:
    row = _row("m24")
    window = row["window"]
    assert isinstance(window, int) and 2 <= window <= 8
    assert row["player_lines"], "M24 needs her version of the player's words"
    assert row["her_lines"], "M24 needs her version of her own lines"
    for line in [*row["player_lines"], *row["her_lines"]]:
        assert isinstance(line, str) and line.strip()
        assert "{" not in line and "}" not in line


def test_m26_sabotage_is_a_display_offset_on_an_audio_bus() -> None:
    row = _row("m26")
    assert row["bus"] == "Music", "docs/05 §1.3 names the music slider"
    offset = row["offset"]
    assert isinstance(offset, (int, float)) and 0 < float(offset) <= 0.1
    # The row is a *display* lie: it may not carry a write target or a value to
    # store, because D20 forbids changing an accommodation and the mix is one.
    assert "writes" not in row
    assert "value" not in row


def test_m22_suggestions_are_authored_sentences() -> None:
    suggestions = DATA["m22"]["suggestions"]
    assert len(suggestions) >= 1
    for line in suggestions:
        assert isinstance(line, str) and line.strip()
        assert "{" not in line and "}" not in line


def test_the_offered_rows_of_this_range_are_still_in_the_catalogue() -> None:
    """M22/M25 are mode O, so their gate lives in the P3.08 catalogue file."""
    events = META_EVENTS["events"]
    assert events["mimic_player"]["meta"] == "M22"
    assert events["mimic_player"]["stage"] == 4
    assert events["hide_ui"]["meta"] == "M25"
    assert events["hide_ui"]["stage"] == 4
    # docs/05 §0 rule 5: both name their accessibility fallback.
    assert "reduced motion" in events["mimic_player"]["fallback"].lower()
    assert "reduced motion" in events["hide_ui"]["fallback"].lower()
    # And both are in-window effects (no OS trick needs a Deep opt-in).
    for action in ("mimic_player", "hide_ui"):
        assert "immersion_deep" not in events[action]
