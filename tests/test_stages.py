"""P2.02 — pin the docs/01 §3 stage machine data.

The GDScript suite (game/tests/StagesTest.gd) proves the behaviour of
GameState/Stages; this file guards the table a reviewer reads without a Godot
build: the bands must be the bible's, the transition must fit docs/01 §3's 2–3 s
window and use names the rest of the data already knows, and every crossing
destination must have a docs/08 §6 EVENT line that passes the docs/01 §4
sensitivity rule.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGES = json.loads((ROOT / "game" / "data" / "stages.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
CASTING = json.loads((ROOT / "game" / "data" / "casting.json").read_text(encoding="utf-8"))
CUE_MAP = json.loads((ROOT / "assets" / "audio" / "cue_map.json").read_text(encoding="utf-8"))

# docs/01_GAME_DESIGN.md §3, verbatim: the band table and the transition window.
DOC_STAGES = ["Honeymoon", "Hairline Cracks", "Leaks", "Fracture", "Collapse", "Terminal"]
DOC_BANDS = [0, 15, 30, 50, 70, 90]
DOC_MIN_DURATION_S = 2.0
DOC_MAX_DURATION_S = 3.0

# docs/01 §4 sensitivity rule; same list tests/test_scenarios.py enforces.
FORBIDDEN_DISORDERS = [
    "bpd",
    "borderline",
    "bipolar",
    "schizo",
    "autis",
    "asperger",
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


def test_stages_table_shape() -> None:
    assert set(STAGES) == {"version", "doc", "bands", "names", "transition"}
    assert STAGES["version"] == 1
    assert STAGES["doc"].strip(), "stages.json carries no doc string"
    assert set(STAGES["transition"]) == {"duration_s", "fx", "cue", "events"}


def test_bands_are_the_bible_bands() -> None:
    bands = STAGES["bands"]
    assert len(bands) == len(DOC_BANDS) == 6, "docs/01 §3 has exactly six stages"
    assert all(isinstance(value, int) for value in bands), "bands are integer floors"
    assert bands == DOC_BANDS
    assert bands[0] == 0
    assert bands == sorted(set(bands)), "floors must be strictly ascending"


def test_band_rows_match_the_design_table() -> None:
    """The doc's Instability column and the data floors cannot drift apart."""
    row = re.compile(r"^\|\s*(\d)\s*\|\s*\*\*([^*]+)\*\*\s*\|\s*(\d+)–(\d+)\s*\|", re.MULTILINE)
    rows = [(int(stage), name, int(low), int(high)) for stage, name, low, high in row.findall(DESIGN)]
    assert [stage for stage, _, _, _ in rows] == list(range(6)), "docs/01 §3 stage table not parsed"
    for stage, name, low, high in rows:
        assert name == DOC_STAGES[stage] == STAGES["names"][stage]
        assert low == STAGES["bands"][stage]
        expected_high = STAGES["bands"][stage + 1] - 1 if stage < 5 else 100
        assert high == expected_high, f"stage {stage} doc range {low}-{high} != data floor range"


def test_transition_is_inside_the_doc_window() -> None:
    transition = STAGES["transition"]
    assert isinstance(transition["duration_s"], (int, float))
    assert DOC_MIN_DURATION_S <= transition["duration_s"] <= DOC_MAX_DURATION_S


def test_transition_uses_known_fx_and_cue_names() -> None:
    """A transition naming something the fx/cue tables do not know is a typo."""
    assert STAGES["transition"]["fx"] in CASTING["fx"], "unknown fx name"
    assert STAGES["transition"]["cue"] in CUE_MAP["system"], "unknown cue name"


def test_every_crossing_has_an_event_line() -> None:
    events = STAGES["transition"]["events"]
    assert sorted(events, key=int) == [str(stage) for stage in range(1, 6)]
    for stage in range(1, 6):
        line = events[str(stage)].strip()
        assert line.startswith("EVENT: "), f"stage {stage} line is not a docs/08 §6 EVENT"
        assert line == events[str(stage)], f"stage {stage} line has stray whitespace"
        assert 0 < len(line) <= 300, f"stage {stage} line is not a prompt-sized sentence"
        assert len(re.findall(r"[.!?](?:\s|$)", line)) <= 3, f"stage {stage} line runs long"


def test_event_lines_respect_the_sensitivity_rule() -> None:
    for stage, line in STAGES["transition"]["events"].items():
        lowered = line.lower()
        for word in FORBIDDEN_DISORDERS:
            assert word not in lowered, f"stage {stage} line names the disorder '{word}'"
