"""P2.01 — pin the meters formula data and the committed 100-turn curve.

The GDScript suite (game/tests/MetersTest.gd) proves the behaviour of
GameState/Meters; this file guards the two artifacts a reviewer reads without a
Godot build: the tuning table and production/handoffs/media/P2.01/meters_curve.*
"""

import csv
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METERS = json.loads((ROOT / "game" / "data" / "meters.json").read_text(encoding="utf-8"))
CURVE = ROOT / "production" / "handoffs" / "media" / "P2.01" / "meters_curve.csv"
PLOT_SCRIPT = ROOT / "tools" / "meters" / "plot.py"

# docs/01_GAME_DESIGN.md §2 and docs/02_DIRECTOR_PROTOCOL.md §1.1, verbatim.
DOC_RATCHET_DROP = 15.0
DOC_SLOW_BURN = {"base": 0.35, "per_fixation": 0.15, "per_lucidity": 0.2}
DOC_DAILY_BURN = 3.0
DOC_MOOD_LIMIT = 3.0
DOC_MOOD_SCALE = {"affection": 1.5, "trust": 2.0, "stress": 0.6}
DOC_TURN_CAPS = {"affection": 5.0, "instability": 3.0}


def test_meters_table_shape() -> None:
    assert set(METERS) == {
        "version",
        "doc",
        "ratchet_drop",
        "slow_burn",
        "daily_burn",
        "mood",
        "writers",
    }
    assert set(METERS["slow_burn"]) == set(DOC_SLOW_BURN)
    assert set(METERS["mood"]) == {"limit", "scale", "turn_caps"}
    assert set(METERS["mood"]["scale"]) == set(DOC_MOOD_SCALE)
    assert set(METERS["mood"]["turn_caps"]) == set(DOC_TURN_CAPS)
    assert set(METERS["writers"]) == {"fixation", "lucidity"}
    assert set(METERS["writers"]["fixation"]) == {
        "time_per_turn",
        "per_affection_gain",
        "isolation",
    }
    assert set(METERS["writers"]["lucidity"]) == {"kindness", "honesty", "boundaries"}


# P2.22B (handoff DCR-1): docs/01 §2 says what moves Fixation ("time spent,
# affection, isolation") and Lucidity ("kindness, honesty, boundaries") but
# never how far, so these magnitudes are this task's tuning — the *only* block
# in meters.json that is not a doc number. They are pinned here so a later task
# changes them on purpose; the doc-number blocks above stay untouched.
WRITER_FIXATION = {
    "time_per_turn": 0.35,
    "per_affection_gain": 0.05,
    "isolation": {"coldness": 0.5, "apathy": 0.5, "ignored_questions": 0.5},
}
WRITER_LUCIDITY = {
    "kindness": {"warmth": 0.3},
    "honesty": {"honesty": 0.8},
    "boundaries": {"boundaries": 1.0},
}
# docs/01 §2's behaviour-profile counters the writers may read, plus the §4
# formula counters (data/paths.json) the keyword rules also write.
_PATHS_DATA = json.loads((ROOT / "game" / "data" / "paths.json").read_text(encoding="utf-8"))
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
} | {
    term["counter"]
    for terms in _PATHS_DATA["scores"].values()
    for term in terms
    if "counter" in term
}


def test_writer_table_matches_the_task_tuning() -> None:
    assert METERS["writers"]["fixation"] == WRITER_FIXATION
    assert METERS["writers"]["lucidity"] == WRITER_LUCIDITY


def test_writers_read_only_documented_counters() -> None:
    writers = METERS["writers"]
    for counter in writers["fixation"]["isolation"]:
        assert counter in PROFILE_COUNTERS
    for group in ("kindness", "honesty", "boundaries"):
        for counter in writers["lucidity"][group]:
            assert counter in PROFILE_COUNTERS, f"unknown writer counter {counter!r}"
    for weight in [
        *writers["fixation"]["isolation"].values(),
        *writers["lucidity"]["kindness"].values(),
        *writers["lucidity"]["honesty"].values(),
        *writers["lucidity"]["boundaries"].values(),
    ]:
        assert isinstance(weight, (int, float)) and weight > 0
    # A turn of time alone must stay smaller than the base slow burn it feeds:
    # if one turn of presence outran the burn's own base, every campaign would
    # be dominated by the clock rather than by how the player behaves.
    assert writers["fixation"]["time_per_turn"] < METERS["slow_burn"]["base"] + 0.15
    assert writers["fixation"]["per_affection_gain"] > 0


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


# docs/01_GAME_DESIGN.md §3 thresholds, verbatim (0-14, 15-29, 30-49, 50-69,
# 70-89, 90-100): on the continuous Instability axis each band runs from its
# floor to the next band's floor.
DOC_STAGE_EDGES = [(0, 15), (15, 30), (30, 50), (50, 70), (70, 90), (90, 100)]


def _load_plot():
    spec = importlib.util.spec_from_file_location("meters_plot", PLOT_SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _svg_rects(text: str) -> list[tuple[float, float, float, float]]:
    found = re.findall(
        r'<rect x="([0-9.]+)" y="([0-9.]+)" width="([0-9.]+)" height="([0-9.]+)"', text
    )
    return [(float(x), float(y), float(w), float(h)) for x, y, w, h in found]


def _stage_runs(rows: list[dict[str, str]]) -> list[tuple[int, int, int]]:
    runs: list[tuple[int, int, int]] = []
    for row in rows:
        turn, stage = int(row["turn"]), int(row["stage"])
        if runs and runs[-1][2] == stage:
            runs[-1] = (runs[-1][0], turn, stage)
        else:
            runs.append((turn, turn, stage))
    return runs


def test_plot_puts_the_stage_bands_on_the_instability_axis(tmp_path: Path) -> None:
    """docs/01 §3 bands are Instability values, never turns (P2.01 DES-1).

    The Instability panel's y axis is the meter, so each band is a full-width
    stripe whose height is the band's share of 0-100; and the strip above it
    spans the turns the CSV is actually in that stage.
    """
    plot = _load_plot()
    out = tmp_path / "meters_curve.svg"
    plot.plot(_curve_rows(), out)
    rects = _svg_rects(out.read_text(encoding="utf-8"))

    bands = sorted(
        (r for r in rects if r[0] == plot.LEFT and r[2] == plot.RIGHT - plot.LEFT),
        key=lambda rect: -rect[1],
    )
    assert len(bands) == len(DOC_STAGE_EDGES), "one full-width y stripe per doc band"
    for (x, y, width, height), (lo, hi) in zip(bands, DOC_STAGE_EDGES):
        assert x == plot.LEFT and width == plot.RIGHT - plot.LEFT
        assert abs(y - plot.y_for(hi, plot.TOP1, plot.HEIGHT1)) < 0.2, f"band {lo}-{hi} top"
        assert abs(height - (hi - lo) / 100.0 * plot.HEIGHT1) < 0.2, f"band {lo}-{hi} height"

    strip = [r for r in rects if r[1] == plot.STRIP_TOP and r[3] == plot.STRIP_HEIGHT]
    runs = _stage_runs(_curve_rows())
    assert len(strip) == len(runs), "one strip segment per CSV stage run"
    for (_x, _y, width, _h), (first, last, _stage) in zip(strip, runs):
        left = max(plot.LEFT, plot.x_for(first - 0.5, 1.0, 100.0))
        right = min(plot.RIGHT, plot.x_for(last + 0.5, 1.0, 100.0))
        assert abs(width - (right - left)) < 0.2, f"strip run {first}-{last} width"

    caption = [line for line in out.read_text(encoding="utf-8").splitlines() if "turn 79/day 11" in line]
    assert caption, "the plot must annotate the stage crossings with their turn and day"
    assert "S5" in caption[0]


# ── P2.22B: the 14-day campaign curve (writers + the retuned T01) ───────────
#
# production/handoffs/media/P2.22B/campaign_curve.csv is written by
# game/tools/campaign_sim.gd (tools/meters/campaign.sh): the real GameState,
# Meters and TriggerEngine driven through three scripted players for 14 days x
# 12 turns (the middle of docs/01 §1's "8–15 exchanges"). It is the evidence
# that the slow burn now has its documented inputs and that Terminal is no
# longer a first-week event — the S2-2 defect the P2.22 live run found
# (Terminal on day 4–5, T01 alone 88 of 130.7 Instability).
CAMPAIGN = ROOT / "production" / "handoffs" / "media" / "P2.22B" / "campaign_curve.csv"
CAMPAIGN_SCENARIOS = ("possessive", "kind", "awake")
CAMPAIGN_DAYS = 14
CAMPAIGN_TURNS_PER_DAY = 12
# docs/01 §1: "14 in-game days"; the last third is what the S2-2 finding asks
# Terminal to land in ("aiming Terminal in the last third").
LAST_THIRD = (10, 14)
# docs/01 §E12: "Remission — Lucidity ≥ 70 at Day 14".
E12_LUCIDITY = 70


def _campaign_rows() -> list[dict[str, str]]:
    with CAMPAIGN.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _scenario_rows(rows: list[dict[str, str]], scenario: str) -> list[dict[str, str]]:
    return [row for row in rows if row["scenario"] == scenario]


def _first_stage(rows: list[dict[str, str]], stage: int) -> dict[str, str] | None:
    return next((row for row in rows if int(row["stage"]) == stage), None)


def test_campaign_curve_is_three_fourteen_day_runs() -> None:
    rows = _campaign_rows()
    assert set(rows[0]) == {
        "scenario",
        "day",
        "turn",
        "read",
        "instability",
        "fixation",
        "lucidity",
        "stage",
        "slow_burn",
        "triggers",
    }
    assert len(rows) == len(CAMPAIGN_SCENARIOS) * CAMPAIGN_DAYS * CAMPAIGN_TURNS_PER_DAY
    for scenario in CAMPAIGN_SCENARIOS:
        run = _scenario_rows(rows, scenario)
        assert len(run) == CAMPAIGN_DAYS * CAMPAIGN_TURNS_PER_DAY
        assert [int(row["day"]) for row in run] == [
            day for day in range(1, CAMPAIGN_DAYS + 1) for _ in range(CAMPAIGN_TURNS_PER_DAY)
        ]
        assert [int(row["turn"]) for row in run] == list(
            range(1, CAMPAIGN_DAYS * CAMPAIGN_TURNS_PER_DAY + 1)
        )
        assert run[-1]["read"], "every turn carries a read label"


def test_campaign_meters_stay_in_range_and_the_burn_uses_them() -> None:
    rows = _campaign_rows()
    for scenario in CAMPAIGN_SCENARIOS:
        run = _scenario_rows(rows, scenario)
        previous_fixation, previous_lucidity = 0.0, 0.0
        previous_stage = 0
        for row in run:
            assert 0.0 <= float(row["instability"]) <= 100.0
            assert 0.0 <= float(row["fixation"]) <= 100.0
            assert 0.0 <= float(row["lucidity"]) <= 100.0
            # The landed slow burn is the docs/01 §2 formula on the inputs the
            # writers had produced by the previous turn: the writers are what
            # the formula was always meant to read.
            expected = (
                DOC_SLOW_BURN["base"]
                + DOC_SLOW_BURN["per_fixation"] * previous_fixation / 100.0
                - DOC_SLOW_BURN["per_lucidity"] * previous_lucidity / 100.0
            )
            burn = float(row["slow_burn"])
            clipped = float(row["instability"]) >= 100.0
            if clipped:
                # At the 100 ceiling only the fitting part of the burn lands.
                assert 0.0 <= burn <= expected + 2e-3, row
            else:
                assert abs(burn - expected) < 2e-3, row
            previous_fixation = float(row["fixation"])
            previous_lucidity = float(row["lucidity"])
            stage = int(row["stage"])
            assert stage >= previous_stage, "stage regressed inside a campaign"
            previous_stage = stage


def test_possessive_terminal_lands_in_the_last_third() -> None:
    run = _scenario_rows(_campaign_rows(), "possessive")
    terminal = _first_stage(run, 5)
    assert terminal is not None, "the possessive run must reach Terminal by day 14"
    day = int(terminal["day"])
    assert LAST_THIRD[0] <= day <= LAST_THIRD[1], (
        f"Terminal landed on day {day}; the P2.22 defect was days 4–5 and the "
        "target is the last third of the 14-day campaign"
    )
    # The stage crossing can happen on the night burn and the next turn's mood
    # may dip the meter afterwards (stage is monotone, the meter is not): the
    # ratchet floor (peak − 15) is the bound, not 90.
    assert float(terminal["instability"]) >= 85.0
    # The writers moved: neither meter is the constant 0 the live run measured.
    assert float(run[-1]["fixation"]) > 40.0
    assert float(run[-1]["lucidity"]) > 20.0


def test_kind_run_reaches_e12_but_never_becomes_the_yandere_fast_path() -> None:
    run = _scenario_rows(_campaign_rows(), "kind")
    assert float(run[-1]["lucidity"]) >= E12_LUCIDITY, "E12 must be reachable by day 14"
    # docs/01 §4.6: she still deteriorates — the kind path is sick by day 14,
    # just slower than the possessive one.
    assert int(run[-1]["stage"]) >= 3
    terminal = _first_stage(run, 5)
    assert terminal is None or int(terminal["day"]) > int(
        _first_stage(_scenario_rows(_campaign_rows(), "possessive"), 5)["day"]
    )


def test_awake_run_reaches_stage_four() -> None:
    run = _scenario_rows(_campaign_rows(), "awake")
    reached = _first_stage(run, 4)
    assert reached is not None, "docs/09 M2: AWAKE reaches stage 4"
    assert int(reached["day"]) <= 12
