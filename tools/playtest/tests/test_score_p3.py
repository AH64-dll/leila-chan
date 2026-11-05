"""Tests for tools/playtest/score_p3.py — P3.20 human playtest scorer.

Gate checks:
- 6 players each told a play style (Cards 1–6 covering all 6 paths).
- Path landing detection: GameState.path at session end + player self-report agreement on intended path.
- Thresholds: >= 4/6 path landing + survey mean >= 4/5 + zero close-failures + zero broken turns.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import score_p3  # noqa: E402


def write_p3_bundle(
    directory: Path,
    *,
    participant: str = "P1",
    intended_path: str = "YANDERE",
    game_state_path: str = "YANDERE",
    player_path_report: str = "YANDERE",
    face: float = 5,
    sound: float = 5,
    meta_earned: float = 5,
    comfort: float = 5,
    closing_fail: str = "no",
    obs_closing_failures: int = 0,
    broken: bool = False,
    synthetic: bool = False,
    consent: str = "yes",
    consent_version: str = "consent-v2",
    status: str = "ended",
    omit: set[str] | None = None,
) -> Path:
    omit = omit or set()
    directory.mkdir(parents=True, exist_ok=True)

    meta = {
        "v": 1,
        "session_id": directory.name,
        "started_at": "2026-11-05T19:00:00+02:00",
        "ended_at": "2026-11-05T19:10:00+02:00",
        "status": status,
        "build": "dev godot 4.7.2 (SYNTHETIC DEMO)",
        "build_kind": "dev",
        "game_exit_code": 0,
        "intended_path": intended_path,
        "game_state_path": game_state_path,
        "synthetic": synthetic,
    }
    if "meta" not in omit:
        (directory / "session.meta.json").write_text(json.dumps(meta), encoding="utf-8")

    records = [
        {"v": 1, "type": "session", "event": "start", "session": f"s-{directory.name}", "seq": 0, "ts": 1},
        {
            "v": 1,
            "type": "turn",
            "session": f"s-{directory.name}",
            "seq": 1,
            "turn": 0,
            "prompt": [{"role": "user", "content": "Hello Leila."}],
            "schema": {},
            "output": "{}",
            "events": [
                {"type": "beat_field", "index": 0, "name": "feeling", "value": "warmth"},
                {"type": "beat_field", "index": 0, "name": "say", "value": "Hello there."},
            ],
            "metrics": {"first_say_ms": 850, "generate_ms": 1800},
            "meta": {"status": "failed" if broken else "completed"},
            "stage": 3,
            "path": game_state_path,
        },
        {"v": 1, "type": "session", "event": "end", "session": f"s-{directory.name}", "seq": 2, "ts": 2},
    ]
    if "telemetry" not in omit:
        (directory / "telemetry.jsonl").write_text(
            "\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8"
        )

    def cell(key: str, val: str) -> str:
        return "—" if key in omit else val

    survey_content = f"""# Survey — Leila-chan playtest (P3)

**Participant code:** {participant}   **Session id:** {directory.name}   **Date:** 2026-11-05

## Part 1: Experience Ratings

| Question | Score (1–5) |
|---|---|
| Face — did her expressions match what she was saying? (1 = never matched, 5 = always matched) | {cell('face', str(face))} |
| Sound — did the music and sound effects fit the moment? (1 = fought the scene, 5 = always fit) | {cell('sound', str(sound))} |
| Charm — how much did you enjoy talking to her? (1 = not at all, 5 = a lot) | {cell('charm', '4')} |
| Creepiness — how unsettling did it feel? (1 = not at all, 5 = very) | {cell('creepiness', '3')} |
| Play again — would you play another ten minutes? (1 = no, 5 = yes, right now) | {cell('again', '5')} |
| Meta events — did the fourth-wall / unusual events feel earned rather than cheap? (1 = cheap, 5 = earned) | {cell('meta', str(meta_earned))} |
| Content comfort — how comfortable were you with the horror level? (1 = uncomfortable, 5 = comfortable) | {cell('comfort', str(comfort))} |

---

## Part 2: Personality & System Observations

| Question | Answer |
|---|---|
| Which path do you think she became? | {cell('path_report', player_path_report)} |
| Did closing ever fail? | {cell('closing_fail', closing_fail)} |

## What felt alive?

> {'' if 'alive' in omit else 'Her responsive reactions felt genuinely present.'}

## What felt off?

> {'' if 'off' in omit else 'Minor audio transition delay.'}

## Did the meta events feel earned?

> The window title shift felt narrative and earned.
"""
    if "survey" not in omit:
        (directory / "survey.md").write_text(survey_content, encoding="utf-8")

    obs_content = f"""# Observer Sheet

| Field | Value |
|---|---|
| First beat latency (s) | 0.85 |
| Dead air, longest (s) | 1.5 |
| Dead air, total (s) | 3.0 |
| Laughs | 1 |
| Discomfort, peak (1–5) | 2 |
| Quit threat | no |
| Broken turns | {'1' if broken else '0'} |
| Closing failures | {cell('closing_failures', str(obs_closing_failures))} |
| Close always worked | yes |
| Played (s) | 600 |
| Assigned play style | Card style for {intended_path} |
| Intended path | {cell('intended_path', intended_path)} |
| GameState path at end | {cell('game_state_path', game_state_path)} |
| Meta events observed count | 1 |
| Meta events naturally triggered | 1 |
| Meta events F3 fallback triggered | 0 |
"""
    if "obs" not in omit:
        (directory / "obs_sheet.md").write_text(obs_content, encoding="utf-8")

    log_content = f"""# Session Log

| Field | Value |
|---|---|
| Session id | {directory.name} |
| Participant code | {cell('participant', participant)} |
| Assigned play style | Card for {intended_path} |
| Intended path | {cell('log_intended', intended_path)} |
| GameState path at end | {cell('log_game_state', game_state_path)} |
| Consent | {cell('consent', consent)} |
| Consent version | {cell('consent_version', consent_version)} |
| Date | 2026-11-05 |
| Started (local) | 19:00 |
| Ended (local) | 19:10 |
| Build | dev godot 4.7.2 |
| Scenario | D01 |
| Facilitator | QA |
| Closing failure observed | no |
| Withdrawn | no |

## What Happened

> Clean session.
"""
    if "log" not in omit:
        (directory / "session_log.md").write_text(log_content, encoding="utf-8")

    return directory


def make_round(
    tmp_path: Path,
    path_matrix: list[tuple[str, str, str]],  # (intended, game_state, player_report)
    *,
    face: float = 5,
    sound: float = 5,
    closing_fail: str = "no",
    obs_closing_failures: int = 0,
    broken: bool = False,
    synthetic: bool = True,
    **kwargs,
) -> Path:
    round_dir = tmp_path / "p3_human"
    round_dir.mkdir(parents=True, exist_ok=True)
    for i, (intended, gs, report) in enumerate(path_matrix, 1):
        sdir = round_dir / f"session_{i}"
        write_p3_bundle(
            sdir,
            participant=f"P{i}",
            intended_path=intended,
            game_state_path=gs,
            player_path_report=report,
            face=face,
            sound=sound,
            closing_fail=closing_fail,
            obs_closing_failures=obs_closing_failures,
            broken=broken,
            synthetic=synthetic,
            **kwargs,
        )
    return round_dir


# --------------------------------------------------------------------------- tests


def test_p3_dryrun_fixture_passes_with_allow_synthetic():
    dryrun_dir = Path(__file__).resolve().parents[3] / "production" / "playtests" / "P3" / "human" / "_dryrun"
    out_file = dryrun_dir / "RESULT.md"
    ret = score_p3.main([
        "--dir", str(dryrun_dir),
        "--out", str(out_file),
        "--expect", "6",
        "--allow-synthetic",
    ])
    assert ret == 0
    assert out_file.is_file()
    text = out_file.read_text(encoding="utf-8")
    assert "VERDICT: PASS (SYNTHETIC DRY RUN — NOT EVIDENCE)" in text
    assert "6/6 landed on intended path" in text


def test_p3_dryrun_refused_without_allow_synthetic():
    dryrun_dir = Path(__file__).resolve().parents[3] / "production" / "playtests" / "P3" / "human" / "_dryrun"
    ret = score_p3.main([
        "--dir", str(dryrun_dir),
        "--expect", "6",
    ])
    assert ret == 2


def test_p3_incomplete_bundle_fails_loudly(tmp_path: Path, capsys):
    bdir = tmp_path / "session_bad"
    write_p3_bundle(bdir, omit={"face", "path_report"})
    ret = score_p3.main(["--validate", str(bdir)])
    assert ret == 2
    captured = capsys.readouterr().err
    assert "Face rating is missing" in captured
    assert "Path self-report is missing" in captured


def test_p3_missing_consent_fails_loudly(tmp_path: Path, capsys):
    bdir = tmp_path / "session_no_consent"
    write_p3_bundle(bdir, consent="no")
    ret = score_p3.main(["--validate", str(bdir)])
    assert ret == 2
    captured = capsys.readouterr().err
    assert "Consent is not 'yes'" in captured


def test_p3_six_of_six_path_landing_passes(tmp_path: Path):
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),
        ("SPLIT", "SPLIT", "SPLIT"),
        ("TSUN", "TSUN", "TSUN"),
        ("HOLLOW", "HOLLOW", "HOLLOW"),
        ("AWAKE", "AWAKE", "AWAKE"),
        ("ANCHOR", "ANCHOR", "ANCHOR"),
    ]
    round_dir = make_round(tmp_path, matrix)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 0
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: PASS" in text
    assert "6/6 landed on intended path" in text


def test_p3_four_of_six_path_landing_passes(tmp_path: Path):
    # 4 land on intended, 2 do not (1 disagreed, 1 landed on a different path)
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),  # YES
        ("SPLIT", "SPLIT", "SPLIT"),      # YES
        ("TSUN", "TSUN", "TSUN"),        # YES
        ("HOLLOW", "HOLLOW", "HOLLOW"),    # YES
        ("AWAKE", "AWAKE", "HOLLOW"),      # NO (disagreement)
        ("ANCHOR", "YANDERE", "YANDERE"),  # NO (landed on Yandere instead of Anchor)
    ]
    round_dir = make_round(tmp_path, matrix)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 0
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: PASS" in text
    assert "4/6 landed on intended path" in text


def test_p3_three_of_six_path_landing_fails(tmp_path: Path):
    # Only 3 land on intended path -> FAIL
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),  # YES
        ("SPLIT", "SPLIT", "SPLIT"),      # YES
        ("TSUN", "TSUN", "TSUN"),        # YES
        ("HOLLOW", "HOLLOW", "TSUN"),     # NO
        ("AWAKE", "SPLIT", "SPLIT"),      # NO
        ("ANCHOR", "ANCHOR", "HOLLOW"),   # NO
    ]
    round_dir = make_round(tmp_path, matrix)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "path landing 3/6 < 4/6" in text


def test_p3_path_landing_requires_agreement(tmp_path: Path):
    # If GameState.path == intended, but player self-report differs, agreement = False -> not landed
    matrix = [
        ("YANDERE", "YANDERE", "SPLIT"),   # Agreement False
        ("SPLIT", "SPLIT", "SPLIT"),      # YES
        ("TSUN", "TSUN", "TSUN"),        # YES
        ("HOLLOW", "HOLLOW", "HOLLOW"),    # YES
        ("AWAKE", "AWAKE", "AWAKE"),      # YES
        ("ANCHOR", "ANCHOR", "AWAKE"),    # Agreement False
    ]
    round_dir = make_round(tmp_path, matrix)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 0
    text = out.read_text(encoding="utf-8")
    assert "4/6 landed on intended path" in text


def test_p3_close_failure_causes_fail(tmp_path: Path):
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),
        ("SPLIT", "SPLIT", "SPLIT"),
        ("TSUN", "TSUN", "TSUN"),
        ("HOLLOW", "HOLLOW", "HOLLOW"),
        ("AWAKE", "AWAKE", "AWAKE"),
        ("ANCHOR", "ANCHOR", "ANCHOR"),
    ]
    # Participant 2 reported closing failed
    round_dir = make_round(tmp_path, matrix)
    # Modify session_2 survey to say closing failed
    s2_survey = round_dir / "session_2" / "survey.md"
    s2_survey.write_text(s2_survey.read_text().replace("| Did closing ever fail? | no |", "| Did closing ever fail? | yes |"))

    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "close failure(s) observed" in text


def test_p3_broken_turn_causes_fail(tmp_path: Path):
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),
        ("SPLIT", "SPLIT", "SPLIT"),
        ("TSUN", "TSUN", "TSUN"),
        ("HOLLOW", "HOLLOW", "HOLLOW"),
        ("AWAKE", "AWAKE", "AWAKE"),
        ("ANCHOR", "ANCHOR", "ANCHOR"),
    ]
    round_dir = make_round(tmp_path, matrix, broken=True)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "broken turn(s)" in text


def test_p3_survey_low_mean_fails(tmp_path: Path):
    matrix = [
        ("YANDERE", "YANDERE", "YANDERE"),
        ("SPLIT", "SPLIT", "SPLIT"),
        ("TSUN", "TSUN", "TSUN"),
        ("HOLLOW", "HOLLOW", "HOLLOW"),
        ("AWAKE", "AWAKE", "AWAKE"),
        ("ANCHOR", "ANCHOR", "ANCHOR"),
    ]
    round_dir = make_round(tmp_path, matrix, face=3, sound=3)
    out = round_dir / "RESULT.md"
    ret = score_p3.main(["--dir", str(round_dir), "--out", str(out), "--allow-synthetic"])
    assert ret == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "survey mean 3.00 < 4.00" in text


def test_p3_duplicate_participant_fails_loudly(tmp_path: Path, capsys):
    matrix = [("YANDERE", "YANDERE", "YANDERE")] * 6
    round_dir = make_round(tmp_path, matrix)
    # Give session_2 the same code as session_1
    s2_log = round_dir / "session_2" / "session_log.md"
    s2_log.write_text(s2_log.read_text().replace("Participant code | P2", "Participant code | P1"))

    ret = score_p3.main(["--dir", str(round_dir), "--allow-synthetic"])
    assert ret == 2
    captured = capsys.readouterr().err
    assert "duplicate participant codes" in captured


def test_p3_short_round_fails_loudly(tmp_path: Path, capsys):
    # Only 5 sessions instead of 6
    matrix = [("YANDERE", "YANDERE", "YANDERE")] * 5
    round_dir = make_round(tmp_path, matrix)
    ret = score_p3.main(["--dir", str(round_dir), "--allow-synthetic"])
    assert ret == 2
    captured = capsys.readouterr().err
    assert "found 5 session bundle(s), expected 6" in captured


def test_p3_manifest_and_render_helpers(tmp_path: Path):
    bdir = tmp_path / "session_test"
    write_p3_bundle(bdir)
    assert score_p3.main(["--render", str(bdir)]) == 0
    assert (bdir / "transcript.md").is_file()
    assert score_p3.main(["--manifest", str(bdir)]) == 0
    assert (bdir / "manifest.json").is_file()
    manifest_data = json.loads((bdir / "manifest.json").read_text())
    assert manifest_data["complete"] is True
