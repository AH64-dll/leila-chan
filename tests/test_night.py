"""P2.19 — pin the day/night loop's content and availability rules to the bible.

The GDScript suites (NightTest, CampaignTest, OvernightEventsTest, NightSceneTest)
prove the behaviour; this file guards the table a reviewer reads without a Godot
build: the two events this phase ships are docs/01 §6.3's N01 and N12, N12's black
screen is the documented ten seconds and ends on the documented line, every
availability block is the scenario contract's shape, and none of the displayed
text names a real disorder or a model brand (docs/01 §4, docs/09 §3).
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NIGHT = json.loads((ROOT / "game" / "data" / "night.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
SCENARIO_DIR = ROOT / "game" / "data" / "scenarios"

STAGES = [str(stage) for stage in range(6)]
DOC_IDS = [f"N{number:02d}" for number in range(1, 13)]
CANONICAL_PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
# docs/01 §4 sensitivity rule; the same list tests/test_stages.py enforces.
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
# docs/09 §3: no model brand appears in game text (the AWAKE factual line is the
# only allowed mention and it lives in the AWAKE prompt module, not here).
FORBIDDEN_BRANDS = ["qwen", "chatgpt", "gpt-", "claude", "gemini", "llama", "deepseek"]

MESSAGE_TIME = re.compile(r"^\d{1,2}:\d{2}\s?[AP]M$")


def _section(number: str) -> str:
    """One docs/01 section body, from its heading to the next heading."""
    pattern = re.compile(
        rf"^#{{2,3}} {re.escape(number)}\b.*?(?=^#{{2,3}} |\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(DESIGN)
    return match.group(0) if match else ""


def _doc_overnight_rows() -> dict:
    """docs/01 §6.3's catalogue: N01..N12 → its description text."""
    rows = {}
    for chunk in _section("6.3").split("·"):
        match = re.search(r"(N\d\d)\s+(.*)$", " ".join(chunk.split()), re.DOTALL)
        if match:
            rows[match.group(1)] = match.group(2).strip()
    return rows


def _event(event_id: str) -> dict:
    for event in NIGHT["events"]:
        if event["id"] == event_id:
            return event
    raise AssertionError(f"night.json has no {event_id}")


def _rows(event: dict) -> list:
    return [row for block in event.get("stage_variants", {}).values() for row in block]


def _displayed_texts() -> list:
    texts = []
    screen = NIGHT["screen"]
    texts.extend(str(value) for value in screen.values() if isinstance(value, str))
    for event in NIGHT["events"]:
        texts.append(event["title"])
        texts.extend(str(row.get("text", "")) for row in _rows(event))
        for row in event.get("path_variants", {}).values():
            texts.append(str(row.get("text", "")))
        if isinstance(event.get("morning_line"), str):
            texts.append(event["morning_line"])
    return [text for text in texts if text]


def test_night_document_shape() -> None:
    assert set(NIGHT) == {"version", "doc", "screen", "events"}
    assert NIGHT["version"] == 1
    assert NIGHT["doc"].strip(), "night.json carries no doc string"
    assert "6.3" in NIGHT["doc"], "the doc string must cite docs/01 §6.3"
    assert isinstance(NIGHT["events"], list) and NIGHT["events"]
    for event in NIGHT["events"]:
        assert {"id", "title", "kind", "available"} <= set(event)
        assert event["kind"] in {"messages", "black"}


def test_ships_the_bibles_n01_and_n12() -> None:
    doc_rows = _doc_overnight_rows()
    assert sorted(doc_rows) == DOC_IDS, "docs/01 §6.3 must name N01..N12"
    shipped = [event["id"] for event in NIGHT["events"]]
    assert shipped == ["N01", "N12"], "this phase ships exactly the two documented events"
    assert set(shipped) <= set(DOC_IDS)
    assert _event("N01")["title"] == doc_rows["N01"]
    assert doc_rows["N12"].startswith(_event("N12")["title"])


def test_n12_is_the_documented_ten_second_black_screen() -> None:
    n12 = _event("N12")
    assert n12["kind"] == "black"
    assert n12["duration_s"] == 10.0, 'docs/01 §6.3: "a black screen for 10 seconds"'
    # The wait is the event: docs/01 §6.3 gives it no skip window.
    assert n12.get("skip_after_s", "absent") is None
    assert n12["morning_line"] == "good morning."
    assert "good morning" in _doc_overnight_rows()["N12"].lower()


def test_every_event_has_a_valid_availability_block() -> None:
    for event in NIGHT["events"]:
        available = event["available"]
        assert set(available) == {"days", "stages", "paths"}
        days = available["days"]
        assert isinstance(days, list) and len(days) == 2
        assert 1 <= days[0] <= days[1] <= 14
        stages = available["stages"]
        assert isinstance(stages, list) and len(stages) == 2
        assert 0 <= stages[0] <= stages[1] <= 5
        paths = available["paths"]
        if isinstance(paths, str):
            assert paths == "any"
        else:
            assert isinstance(paths, list) and paths
            assert set(paths) <= set(CANONICAL_PATHS)


def test_message_rows_cover_every_stage() -> None:
    n01 = _event("N01")
    assert n01["kind"] == "messages"
    assert n01["message_interval_s"] > 0
    variants = n01["stage_variants"]
    assert set(variants) <= set(STAGES)
    # Every stage resolves through the highest-defined-variant rule, so all six
    # stages must have a block to fall back to.
    assert set(variants) == set(STAGES), "N01 needs a line for every stage 0-5"
    for stage, rows in variants.items():
        assert rows, f"N01 stage {stage} is empty"
        for row in rows:
            assert MESSAGE_TIME.match(row["time"]), row["time"]
            assert row["text"].strip(), f"N01 stage {stage} has an empty line"


def test_path_variants_are_canonical() -> None:
    for event in NIGHT["events"]:
        for path_id, row in event.get("path_variants", {}).items():
            assert path_id in CANONICAL_PATHS
            assert row["text"].strip()


def test_screen_chrome_is_complete() -> None:
    screen = NIGHT["screen"]
    assert "{day}" in screen["day_label"]
    assert "{time}" in screen["message_format"] and "{text}" in screen["message_format"]
    for key in ("night_label", "morning_line", "skip_hint"):
        assert screen[key].strip()
    assert screen["skip_after_s"] >= 0
    assert screen["hold_s"] > 0


def test_displayed_text_respects_the_sensitivity_and_brand_rules() -> None:
    for text in _displayed_texts():
        lowered = text.lower()
        for word in FORBIDDEN_DISORDERS:
            assert word not in lowered, f"{word!r} in night text: {text!r}"
        for brand in FORBIDDEN_BRANDS:
            assert brand not in lowered, f"{brand!r} in night text: {text!r}"


def test_shipped_scenarios_keep_the_availability_contract() -> None:
    files = sorted(SCENARIO_DIR.glob("*.json"))
    assert files, "no scenarios are shipped"
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        available = data["available"]
        days = available["days"]
        stages = available["stages"]
        assert 1 <= days[0] <= days[1] <= 14, path.name
        assert 0 <= stages[0] <= stages[1] <= 5, path.name
        paths = available["paths"]
        if isinstance(paths, str):
            assert paths == "any", path.name
        else:
            assert paths and set(paths) <= set(CANONICAL_PATHS), path.name
