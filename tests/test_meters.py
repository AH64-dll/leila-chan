"""P2.01 — pin the meters formula data and the committed 100-turn curve.

The GDScript suite (game/tests/MetersTest.gd) proves the behaviour of
GameState/Meters; this file guards the two artifacts a reviewer reads without a
Godot build: the tuning table and production/handoffs/media/P2.01/meters_curve.*
"""

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METERS = json.loads((ROOT / "game" / "data" / "meters.json").read_text(encoding="utf-8"))
CURVE = ROOT / "production" / "handoffs" / "media" / "P2.01" / "meters_curve.csv"

# docs/01_GAME_DESIGN.md §2 and docs/02_DIRECTOR_PROTOCOL.md §1.1, verbatim.
DOC_RATCHET_DROP = 15.0
DOC_SLOW_BURN = {"base": 0.35, "per_fixation": 0.15, "per_lucidity": 0.2}
DOC_DAILY_BURN = 3.0
DOC_MOOD_LIMIT = 3.0
DOC_MOOD_SCALE = {"affection": 1.5, "trust": 2.0, "stress": 0.6}
DOC_TURN_CAPS = {"affection": 5.0, "instability": 3.0}


def test_meters_table_shape() -> None:
    assert set(METERS) == {"version", "doc", "ratchet_drop", "slow_burn", "daily_burn", "mood"}
    assert set(METERS["slow_burn"]) == set(DOC_SLOW_BURN)
    assert set(METERS["mood"]) == {"limit", "scale", "turn_caps"}
    assert set(METERS["mood"]["scale"]) == set(DOC_MOOD_SCALE)
    assert set(METERS["mood"]["turn_caps"]) == set(DOC_TURN_CAPS)


def test_meters_table_matches_docs() -> None:
    assert METERS["ratchet_drop"] == DOC_RATCHET_DROP
    assert METERS["daily_burn"] == DOC_DAILY_BURN
    assert METERS["slow_burn"] == DOC_SLOW_BURN
    assert METERS["mood"]["limit"] == DOC_MOOD_LIMIT
    assert METERS["mood"]["scale"] == DOC_MOOD_SCALE
    assert METERS["mood"]["turn_caps"] == DOC_TURN_CAPS


def _curve_rows() -> list[dict[str, str]]:
    with CURVE.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_curve_is_a_100_turn_campaign() -> None:
    rows = _curve_rows()
    assert len(rows) == 100
    assert [int(row["turn"]) for row in rows] == list(range(1, 101))
    assert sorted({int(row["day"]) for row in rows}) == list(range(1, 15))
    assert rows[-1]["read"]


def test_curve_ratchet_and_ranges_hold_every_turn() -> None:
    rows = _curve_rows()
    previous_peak = 0.0
    previous_stage = 0
    for row in rows:
        instability = float(row["instability"])
        floor = float(row["instability_floor"])
        peak = float(row["instability_peak"])
        assert instability >= floor - 1e-6, f"ratchet violated at turn {row['turn']}"
        assert abs(floor - max(0.0, peak - DOC_RATCHET_DROP)) < 1e-3
        assert 0.0 <= instability <= 100.0
        assert 0.0 <= float(row["affection"]) <= 100.0
        assert -50.0 <= float(row["trust"]) <= 50.0
        assert 0.0 <= float(row["fixation"]) <= 100.0
        assert 0.0 <= float(row["lucidity"]) <= 100.0
        assert peak >= previous_peak - 1e-6, f"peak fell at turn {row['turn']}"
        stage = int(row["stage"])
        assert stage >= previous_stage, f"stage regressed at turn {row['turn']}"
        assert 0 <= stage <= 5
        previous_peak = peak
        previous_stage = stage


def test_curve_burns_match_docs() -> None:
    rows = _curve_rows()
    for row in rows:
        expected = (
            DOC_SLOW_BURN["base"]
            + DOC_SLOW_BURN["per_fixation"] * float(row["fixation"]) / 100.0
            - DOC_SLOW_BURN["per_lucidity"] * float(row["lucidity"]) / 100.0
        )
        # slow_burn is the delta that landed: the formula, clipped only by the
        # 100 ceiling the meter was at when the burn ran (instability_pre).
        landed = min(expected, 100.0 - float(row["instability_pre"]))
        assert abs(float(row["slow_burn"]) - landed) < 2e-3


def test_curve_plot_artifacts_exist() -> None:
    svg = CURVE.with_suffix(".svg")
    png = CURVE.with_suffix(".png")
    assert svg.exists() and svg.stat().st_size > 4000
    assert "<svg" in svg.read_text(encoding="utf-8")
    assert png.exists() and png.stat().st_size > 4000
