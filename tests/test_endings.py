"""P3.16 — pin the endings table and its UI strings to the design bible.

The GDScript suites (EndingsTest, EndingLogTest, EndingSceneTest, ExtrasSceneTest)
prove the behaviour; this file guards the data a reviewer reads without a Godot
build: docs/01 §7's fourteen rows in the bible's order with the bible's names and
paths, the numbers the bible does state, the condition vocabulary the evaluator
understands, the per-path fallbacks that stand in where the bible is silent, the
secret's "play all six paths" rule, and the absence of a real disorder name or a
model brand in anything a player can read.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENDINGS = json.loads((ROOT / "game" / "data" / "endings.json").read_text(encoding="utf-8"))
UI = json.loads((ROOT / "game" / "data" / "ui.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")

CANONICAL_PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
ANY_PATH = "ANY"
CONDITION_KEYS = {"stage_min", "stage_max", "day_min", "day_max", "meters", "counters", "flags", "not_flags"}
AT_TIMES = {"campaign_end", "any_time"}
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
# docs/09 §3: the only allowed model mention is the AWAKE factual line.
FORBIDDEN_BRANDS = ["qwen", "alibaba", "chatgpt", "claude", "openai", "anthropic"]


def _doc_rows() -> list[tuple[str, str, str, str]]:
    """docs/01 §7's table as (id, name, path, condition prose), in doc order."""
    rows = re.findall(r"^\| (E\d{2}) \| \*\*(.+?)\*\* \| (\w+) \| (.+?) \|$", DESIGN, re.MULTILINE)
    assert len(rows) == 14, f"docs/01 §7 should list fourteen endings, found {len(rows)}"
    return rows


def _row(ending_id: str) -> dict:
    for row in ENDINGS["endings"]:
        if row["id"] == ending_id:
            return row
    raise AssertionError(f"endings.json has no {ending_id}")


def _ending_rows() -> list[dict]:
    return [row for row in ENDINGS["endings"] if row["kind"] == "ending"]


def test_the_table_is_the_bible() -> None:
    doc = _doc_rows()
    data = _ending_rows()
    assert [row["id"] for row in data] == [row[0] for row in doc]
    assert [row["name"] for row in data] == [row[1] for row in doc]
    # E14's doc cell says "Any"; the data's canonical spelling is the evaluator's.
    assert [row["path"] for row in data] == [row[2].upper() for row in doc]
    for row in data:
        assert row["kind"] == "ending"
        assert isinstance(row["priority"], int) and row["priority"] >= 0
        assert row["at"] in AT_TIMES
        assert isinstance(row["condition"], dict)


def test_the_bibles_numbers_are_the_data() -> None:
    # "Affection ≥ 80 at Terminal"
    assert _row("E01")["condition"]["meters"]["affection"]["min"] == 80
    assert _row("E01")["condition"]["stage_min"] == 5
    # "Lucidity ≥ 70 at Day 14"
    assert _row("E12")["condition"]["meters"]["lucidity"]["min"] == 70
    assert _row("E12")["condition"]["day_min"] == 14
    # "Instability 100 before Day 7" — before day 7 means day ≤ 6.
    assert _row("E14")["condition"]["meters"]["instability"]["min"] == 100
    assert _row("E14")["condition"]["day_max"] == 6


def test_every_condition_uses_the_vocabulary() -> None:
    for row in ENDINGS["endings"]:
        if row["kind"] != "ending":
            continue
        condition = row["condition"]
        assert set(condition) <= CONDITION_KEYS, row["id"]
        for key in ("stage_min", "stage_max", "day_min", "day_max"):
            if key in condition:
                assert isinstance(condition[key], (int, float)), (row["id"], key)
        for block in ("meters", "counters"):
            for name, bounds in condition.get(block, {}).items():
                assert set(bounds) <= {"min", "max"}, (row["id"], name)
                assert bounds, (row["id"], name)
                for edge in bounds.values():
                    assert isinstance(edge, (int, float)), (row["id"], name)
        if "flags" in condition:
            assert isinstance(condition["flags"], dict)
        if "not_flags" in condition:
            assert isinstance(condition["not_flags"], list)


def test_every_path_has_a_fallback_that_exists() -> None:
    defaults = ENDINGS["defaults"]
    assert set(defaults) == set(CANONICAL_PATHS) | {"any"}
    by_id = {row["id"]: row for row in _ending_rows()}
    for path in CANONICAL_PATHS:
        fallback = by_id[defaults[path]]
        assert fallback["path"] == path, f"{path}'s fallback is {fallback['id']}"
    assert by_id[defaults["any"]]["path"] == ANY_PATH


def test_every_path_has_at_least_one_specific_row() -> None:
    for path in CANONICAL_PATHS:
        rows = [row for row in _ending_rows() if row["path"] == path]
        assert rows, f"no ending belongs to {path}"


def test_static_is_the_only_any_time_row_and_outranks_everything() -> None:
    any_time = [row for row in _ending_rows() if row["at"] == "any_time"]
    assert [row["id"] for row in any_time] == ["E14"]
    assert _row("E14")["path"] == ANY_PATH
    assert _row("E14")["priority"] == min(row["priority"] for row in _ending_rows())


def test_the_secret_asks_for_the_six_paths() -> None:
    secret = [row for row in ENDINGS["endings"] if row["kind"] == "secret"]
    assert len(secret) == 1
    row = secret[0]
    assert row["id"] == "SECRET"
    assert row["name"] == "Weights"
    assert row["path"] == ANY_PATH
    assert row["requires"]["paths"] == CANONICAL_PATHS
    # The bible's own line for it, so the data cannot invent a different rule.
    assert re.search(r'\*\*Secret ending .{1,3} "Weights":\*\* play all 6 paths', DESIGN)


def test_no_real_disorder_is_named() -> None:
    for row in ENDINGS["endings"]:
        text = " ".join(
            str(row.get(key, "")) for key in ("name", "frame", "card", "detail")
        ).lower()
        for word in FORBIDDEN_DISORDERS:
            assert word not in text, (row["id"], word)


def test_no_model_brand_appears() -> None:
    for row in ENDINGS["endings"]:
        text = " ".join(
            str(row.get(key, "")) for key in ("name", "frame", "card", "detail")
        ).lower()
        for brand in FORBIDDEN_BRANDS:
            assert brand not in text, (row["id"], brand)


def test_the_ui_strings_exist() -> None:
    assert UI["title"]["btn_extras"] == "Extras"
    ending = UI["ending"]
    for key in (
        "title_fallback",
        "path_format",
        "any_path",
        "seen_first",
        "seen_format",
        "unknown",
        "skip_hint",
    ):
        assert ending[key].strip(), key
    # The reveal and the skip window are data, never wall-clock guesses.
    assert isinstance(ending["line_interval_s"], (int, float))
    assert ending["line_interval_s"] > 0
    assert isinstance(ending["skip_after_s"], (int, float))
    assert ending["skip_after_s"] > 0
    extras = UI["extras"]
    for key in (
        "title",
        "subtitle",
        "progress",
        "locked",
        "locked_detail",
        "detail_format",
        "detail_first",
        "secret_title",
        "secret_locked",
        "secret_unlocked",
        "empty",
        "btn_back",
    ):
        assert extras[key].strip(), key
    assert extras["locked"] == "???"
