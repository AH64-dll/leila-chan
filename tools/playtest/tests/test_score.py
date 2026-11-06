"""Tests for tools/playtest/score.py — the P2 human-round scorer.

Run: python -m pytest tools/playtest/tests -q

The three gate cases the brief names are covered first: an incomplete bundle fails loudly,
a 4/5 round passes, a 3/5 round fails. The rest pins the edges that would otherwise let a
bad round through: a broken turn, a synthetic bundle without the flag, and a short round.
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
# tools/promptlab/score.py shares this module name; the first import wins
# sys.modules for the whole session, so drop it before importing this dir's.
sys.modules.pop("score", None)
import score  # noqa: E402  (path set above)


def write_bundle(
    directory: Path,
    *,
    face: float = 4,
    sound: float = 4,
    synthetic: bool = False,
    broken: bool = False,
    omit: set[str] | None = None,
    consent: str = "yes",
) -> Path:
    """A minimal but complete session bundle, shaped like a real one."""
    omit = omit or set()
    directory.mkdir(parents=True, exist_ok=True)
    meta = {
        "v": 1,
        "session_id": directory.name,
        "started_at": "2026-11-05T19:00:00+02:00",
        "ended_at": "2026-11-05T19:10:00+02:00",
        "status": "ended",
        "build": "test build",
        "build_kind": "dev",
        "game_exit_code": 0,
        "synthetic": synthetic,
    }
    (directory / "session.meta.json").write_text(json.dumps(meta), encoding="utf-8")

    records = [
        {"v": 1, "type": "session", "event": "start", "session": "s1-001", "seq": 0, "ts": 1},
        {
            "v": 1,
            "type": "turn",
            "session": "s1-001",
            "seq": 1,
            "turn": 0,
            "prompt": [{"role": "user", "content": "Hi."}],
            "schema": {},
            "output": "{}",
            "events": [
                {"type": "beat_field", "index": 0, "name": "feeling", "value": "shy"},
                {"type": "beat_field", "index": 0, "name": "say", "value": "Oh! Hello."},
            ],
            "metrics": {"first_say_ms": 900, "generate_ms": 2000},
            "meta": {"status": "failed" if broken else "completed"},
            "stage": 0,
        },
        {"v": 1, "type": "session", "event": "end", "session": "s1-001", "seq": 1, "ts": 2},
    ]
    (directory / "telemetry.jsonl").write_text(
        "\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8"
    )

    def cell(key: str, value: str) -> str:
        return "—" if key in omit else value

    (directory / "survey.md").write_text(
        "# Survey\n\n"
        "| Question | Score (1–5) |\n|---|---|\n"
        f"| Face — did her expressions match what she said? | {cell('face', str(face))} |\n"
        f"| Sound — did the music fit the moment? | {cell('sound', str(sound))} |\n"
        f"| Charm — how much did you enjoy talking to her? | {cell('charm', '4')} |\n"
        f"| Creepiness — how unsettling did it feel? | {cell('creepiness', '2')} |\n"
        f"| Play again — would you play another ten minutes? | {cell('play', '4')} |\n\n"
        "## What felt alive?\n\n> The pause before she answered.\n\n"
        f"## What felt off?\n\n{'' if 'off' in omit else '> Nothing much.'}\n",
        encoding="utf-8",
    )

    (directory / "obs_sheet.md").write_text(
        "# Observer\n\n"
        "| Field | Value |\n|---|---|\n"
        "| First beat latency (s) | 1.2 |\n"
        "| Dead air, longest (s) | 3.0 |\n"
        "| Dead air, total (s) | 6.0 |\n"
        "| Laughs | 1 |\n"
        "| Discomfort, peak (1–5) | 2 |\n"
        "| Quit threat | no |\n"
        f"| Broken turns | {'1' if broken else '0'} |\n"
        "| Played (s) | 600 |\n",
        encoding="utf-8",
    )

    (directory / "session_log.md").write_text(
        "# Session log\n\n"
        "| Field | Value |\n|---|---|\n"
        f"| Session id | {directory.name} |\n"
        f"| Participant code | P{directory.name[-1]} |\n"
        f"| Consent | {consent} |\n"
        "| Consent version | consent-v1 |\n"
        "| Date | 2026-11-05 |\n"
        "| Started (local) | 19:00 |\n"
        "| Ended (local) | 19:10 |\n"
        "| Build | test build |\n"
        "| Facilitator | QA |\n",
        encoding="utf-8",
    )
    return directory


def make_round(tmp_path: Path, scores: list[tuple[float, float]], **kwargs) -> Path:
    round_dir = tmp_path / "human"
    round_dir.mkdir()
    for index, (face, sound) in enumerate(scores, 1):
        write_bundle(round_dir / f"session_{index}", face=face, sound=sound, **kwargs)
    return round_dir


def test_incomplete_bundle_fails_loudly(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    broken_survey = round_dir / "session_2" / "survey.md"
    broken_survey.write_text(
        broken_survey.read_text(encoding="utf-8").replace("| 4 |", "| — |", 1), encoding="utf-8"
    )
    out = round_dir / "RESULT.md"

    code = score.main(["--dir", str(round_dir), "--out", str(out)])

    assert code == 2
    assert not out.exists(), "an incomplete round must never produce a verdict file"
    stderr = capsys.readouterr().err
    assert "INCOMPLETE session_2" in stderr
    assert "survey.md" in stderr
    assert "Face rating" in stderr


def test_blank_charm_row_is_not_masked_by_the_face_row(tmp_path, capsys):
    """Regression: a bare-string needle used to match any key containing its letters,
    so a blank Charm row was silently filled with the Face score."""
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    survey = round_dir / "session_1" / "survey.md"
    survey.write_text(
        survey.read_text(encoding="utf-8").replace("| 4 |\n| Creepiness", "| — |\n| Creepiness", 1),
        encoding="utf-8",
    )

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    stderr = capsys.readouterr().err
    assert "Charm rating is missing" in stderr
    assert "Face rating is missing" not in stderr


def test_missing_consent_is_incomplete(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    log = round_dir / "session_3" / "session_log.md"
    log.write_text(log.read_text(encoding="utf-8").replace("| Consent | yes |", "| Consent | no |"),
                   encoding="utf-8")

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    assert "Consent is not 'yes'" in capsys.readouterr().err


def test_empty_telemetry_is_incomplete(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    (round_dir / "session_1" / "telemetry.jsonl").write_text("", encoding="utf-8")

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    assert "0 turn records" in capsys.readouterr().err


def test_four_of_five_passes(tmp_path):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    out = round_dir / "RESULT.md"

    code = score.main(["--dir", str(round_dir), "--out", str(out)])

    assert code == 0
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: PASS" in text
    assert "| Survey mean (Face + Sound, pooled over 6 ratings) | 4.00 | ≥ 4.00 | PASS |" in text
    assert "| Broken turns (observer and telemetry, worst of) | 0 | 0 | PASS |" in text


def test_three_of_five_fails(tmp_path):
    round_dir = make_round(tmp_path, [(3, 3), (3, 3), (3, 3)])
    out = round_dir / "RESULT.md"

    code = score.main(["--dir", str(round_dir), "--out", str(out)])

    assert code == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "survey mean 3.00 < 4.00" in text


def test_broken_turn_blocks_pass(tmp_path):
    round_dir = make_round(tmp_path, [(5, 5), (5, 5), (5, 5)], broken=True)
    out = round_dir / "RESULT.md"

    code = score.main(["--dir", str(round_dir), "--out", str(out)])

    assert code == 1
    text = out.read_text(encoding="utf-8")
    assert "VERDICT: FAIL" in text
    assert "3 broken turn(s)" in text


def test_synthetic_bundle_needs_the_flag(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)], synthetic=True)

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    assert "--allow-synthetic" in capsys.readouterr().err

    code = score.main(
        ["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md"), "--allow-synthetic"]
    )
    assert code == 0
    assert "SYNTHETIC DRY RUN — NOT EVIDENCE" in (round_dir / "RESULT.md").read_text(encoding="utf-8")


def test_duplicate_participant_code_is_refused(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    log = round_dir / "session_2" / "session_log.md"
    log.write_text(log.read_text(encoding="utf-8").replace("| Participant code | P2 |",
                                                           "| Participant code | P1 |"),
                   encoding="utf-8")

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    assert "duplicate participant codes" in capsys.readouterr().err


def test_short_round_is_refused(tmp_path, capsys):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4)])

    code = score.main(["--dir", str(round_dir), "--out", str(round_dir / "RESULT.md")])

    assert code == 2
    assert "expected 3" in capsys.readouterr().err


def test_no_bundles_is_refused(tmp_path, capsys):
    empty = tmp_path / "human"
    empty.mkdir()

    code = score.main(["--dir", str(empty)])

    assert code == 2
    assert "no session bundles" in capsys.readouterr().err


def test_dryrun_directories_are_never_scanned(tmp_path):
    round_dir = make_round(tmp_path, [(4, 4), (4, 4), (4, 4)])
    write_bundle(round_dir / "_dryrun" / "session_fake", face=1, sound=1, synthetic=True)
    out = round_dir / "RESULT.md"

    code = score.main(["--dir", str(round_dir), "--out", str(out)])

    assert code == 0, "the _dryrun fixture must not be counted as a fourth session"
    assert "VERDICT: PASS" in out.read_text(encoding="utf-8")


def test_transcript_render_reads_player_and_beats(tmp_path):
    bundle = write_bundle(tmp_path / "session_1")
    assert score.main(["--render", str(bundle)]) == 0
    text = (bundle / "transcript.md").read_text(encoding="utf-8")
    assert "**Player:** Hi." in text
    assert "shy/" in text and "Oh! Hello." in text


def test_generated_dryrun_bundle_scores(tmp_path):
    """The committed fixture under production/playtests/P2/human/_dryrun must stay valid."""
    fixture = score.DEFAULT_DIR / "_dryrun"
    if not (fixture / "session_1" / "session.meta.json").is_file():
        pytest.skip("no committed dry-run fixture")
    out = tmp_path / "RESULT.md"

    code = score.main(
        ["--dir", str(fixture), "--expect", "1", "--allow-synthetic", "--out", str(out)]
    )

    assert code == 0
    assert "SYNTHETIC DRY RUN — NOT EVIDENCE" in out.read_text(encoding="utf-8")
