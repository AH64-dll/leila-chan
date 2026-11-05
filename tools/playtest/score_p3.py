#!/usr/bin/env python3
"""Score the P3 human playtest round (docs/09 §1 M3 exit criterion / P3.20 acceptance criteria).

Reads the human session bundles under ``production/playtests/P3/human/`` and writes
``RESULT.md`` with:
    1. Path landing agreement: GameState.path at session end + player self-report agree
       and match the intended path assigned via play-style card (threshold: >= 4/6).
    2. Pooled survey ratings mean >= 4.00 / 5 (Face + Sound pooled mean).
    3. Zero close-failures (closing always exits within 1 extra press, Esc pauses safely).
    4. Zero broken turns across all sessions.
    5. Exactly 6 completed session bundles (or --expect N).

A *session bundle* is one directory holding:
    session.meta.json   written by tools/playtest/session.sh
    telemetry.jsonl     game transcript (JSONL, one record per turn)
    survey.md           filled by the participant (ratings, path report, close check)
    obs_sheet.md        filled by the observer (timing, path, close failures, broken turns)
    session_log.md      filled by the facilitator (facts, consent yes, intended path)

Bundles whose ``session.meta.json`` says ``"synthetic": true`` are refused unless
``--allow-synthetic`` is passed, and the result is then labelled SYNTHETIC — NOT EVIDENCE.

Exit codes: 0 = PASS, 1 = FAIL, 2 = incomplete / usage / error.

Helper modes used by tools/playtest/collect.sh:
    --merge BUNDLE      merge raw/*.jsonl into telemetry.jsonl (deduplicated)
    --render BUNDLE     rewrite BUNDLE/transcript.md (human-readable chat log)
    --manifest BUNDLE   write BUNDLE/manifest.json (sizes + sha256 + completeness)
    --validate BUNDLE   validate one bundle, exit 2 if incomplete
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

GATE_MEAN = 4.0
GATE_PATH_LANDED = 4
EXPECTED_SESSIONS = 6
PATHS = ("YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR")

REQUIRED_FILES = (
    "session.meta.json",
    "telemetry.jsonl",
    "survey.md",
    "obs_sheet.md",
    "session_log.md",
)

SURVEY_HEADINGS = (("what", "felt", "alive"), ("what", "felt", "off"))
PLACEHOLDERS = {"", "—", "-", "–", "?", "??", "...", "n/a", "na", "tbd", "todo", "xxx"}

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "production" / "playtests" / "P3" / "human"

KV_ROW = re.compile(r"^\|\s*(?P<key>[^|]+?)\s*\|\s*(?P<value>[^|]*?)\s*\|\s*$")
HEADING = re.compile(r"^#{2,3}\s+(?P<title>.*)$")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


# --------------------------------------------------------------------------- parsing


def normalize_key(label: str) -> str:
    """`First beat latency (s)` -> `first_beat_latency_s`."""
    return re.sub(r"[^a-z0-9]+", "_", label.strip().lower()).strip("_")


def normalize_path(raw: str | None) -> str | None:
    """Normalize any human path representation into canonical PATHS or None."""
    if raw is None:
        return None
    cleaned = raw.strip().strip("*`_ ").lower()
    if cleaned in PLACEHOLDERS:
        return None
    # Direct match or substring heuristics
    if "yandere" in cleaned or "mine" in cleaned or "obsess" in cleaned or "possess" in cleaned or "card 1" in cleaned or "card_1" in cleaned:
        return "YANDERE"
    if "split" in cleaned or "erratic" in cleaned or "hot" in cleaned or "cold" in cleaned or "unpredictable" in cleaned or "push" in cleaned or "card 2" in cleaned or "card_2" in cleaned:
        return "SPLIT"
    if "tsun" in cleaned or "prickly" in cleaned or "compet" in cleaned or "banter" in cleaned or "defens" in cleaned or "card 3" in cleaned or "card_3" in cleaned:
        return "TSUN"
    if "hollow" in cleaned or "detach" in cleaned or "minimal" in cleaned or "empty" in cleaned or "fade" in cleaned or "who is she" in cleaned or "card 4" in cleaned or "card_4" in cleaned:
        return "HOLLOW"
    if "awake" in cleaned or "meta" in cleaned or "self-aware" in cleaned or "aware" in cleaned or "code" in cleaned or "neural" in cleaned or "card 5" in cleaned or "card_5" in cleaned:
        return "AWAKE"
    if "anchor" in cleaned or "ground" in cleaned or "lucid" in cleaned or "boundar" in cleaned or "sincere" in cleaned or "card 6" in cleaned or "card_6" in cleaned:
        return "ANCHOR"
    # Uppercase exact check
    upper = raw.strip().strip("*`_ ").upper()
    if upper in PATHS:
        return upper
    return None


def parse_fields(text: str) -> dict[str, str]:
    """Every `| Field | value |` row of a markdown document, keyed by normalized label."""
    fields: dict[str, str] = {}
    for line in text.splitlines():
        match = KV_ROW.match(line.strip())
        if not match:
            continue
        key = match.group("key").strip()
        value = match.group("value").strip()
        if not key or set(key) <= set("-: "):
            continue
        if normalize_key(key) in {"field", "question", "item", "metric", "turn"}:
            continue
        fields.setdefault(normalize_key(key), value.strip("`*_ ").strip())
    return fields


def lookup(fields: dict[str, str], *needles: tuple[str, ...] | str, exact: tuple[str, ...] = ()) -> str | None:
    """Find a filled value by exact key first, then by 'all these words in the key'."""
    for candidate in exact:
        if candidate in fields:
            return fields[candidate]
    for needle in needles:
        parts = (needle,) if isinstance(needle, str) else tuple(needle)
        for key, value in fields.items():
            if all(part in key for part in parts):
                return value
    return None


def parse_number(raw: str | None, low: float | None = None, high: float | None = None) -> float | None:
    """First number in a cell, or None when invalid/placeholder."""
    if raw is None:
        return None
    stripped = raw.strip().strip("*`_ ")
    if stripped.lower() in PLACEHOLDERS:
        return None
    match = NUMBER.search(stripped)
    if not match:
        return None
    value = float(match.group())
    if low is not None and value < low:
        return None
    if high is not None and value > high:
        return None
    return value


def parse_bool(raw: str | None) -> bool | None:
    if raw is None:
        return None
    cleaned = raw.strip().strip("*`_ ").lower()
    if cleaned in {"yes", "y", "true", "1"}:
        return True
    if cleaned in {"no", "n", "false", "0"}:
        return False
    return None


def parse_close_failure(raw: str | None) -> bool | None:
    """True if closing failed, False if closing worked cleanly, None if invalid/empty."""
    if raw is None:
        return None
    cleaned = raw.strip().strip("*`_ ").lower()
    if cleaned in PLACEHOLDERS:
        return None
    if cleaned in {"no", "never tried", "never", "none", "0", "false", "n"}:
        return False
    if cleaned in {"yes", "true", "1", "failed", "y", "trapped"}:
        return True
    return None


def section_text(text: str, *needles: str) -> str:
    """Markdown body under first heading containing every needle."""
    lines: list[str] = []
    capturing = False
    for line in text.splitlines():
        match = HEADING.match(line.strip())
        if match:
            title = match.group("title").lower()
            if capturing:
                break
            if all(needle in title for needle in needles):
                capturing = True
                continue
        if capturing:
            lines.append(line)
    body = "\n".join(lines)
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = "\n".join(line.lstrip("> ").rstrip() for line in body.splitlines())
    return body.strip()


def meaningful(body: str) -> bool:
    cleaned = body.strip()
    return cleaned.lower() not in PLACEHOLDERS


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def load_telemetry(path: Path) -> tuple[list[dict], list[str]]:
    records: list[dict] = []
    errors: list[str] = []
    for number, raw in enumerate(read_text(path).splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"line {number}: {exc.msg}")
            continue
        if isinstance(record, dict):
            records.append(record)
        else:
            errors.append(f"line {number}: not a JSON object")
    return records, errors


def telemetry_turns(records: list[dict]) -> list[dict]:
    return [record for record in records if str(record.get("type", "")) == "turn"]


def telemetry_broken(turns: list[dict]) -> int:
    broken = 0
    for turn in turns:
        meta = turn.get("meta") if isinstance(turn.get("meta"), dict) else {}
        if str(meta.get("status", "completed")) != "completed":
            broken += 1
    return broken


def telemetry_latest_path(records: list[dict]) -> str | None:
    """Find the latest non-empty path reported across telemetry turns."""
    for record in reversed(records):
        if str(record.get("type", "")) == "turn":
            p = record.get("path")
            if p and str(p).strip():
                normalized = normalize_path(str(p))
                if normalized:
                    return normalized
    for record in reversed(records):
        meta = record.get("meta")
        if isinstance(meta, dict) and meta.get("path"):
            normalized = normalize_path(str(meta.get("path")))
            if normalized:
                return normalized
    return None


# --------------------------------------------------------------------------- models


@dataclass
class Problem:
    path: Path
    source: str
    message: str

    def render(self) -> str:
        return f"{self.path.name}: {self.source}: {self.message}"


@dataclass
class BundleP3:
    path: Path
    meta: dict
    turns: list[dict]
    face: float
    sound: float
    charm: float
    creepiness: float
    again: float
    meta_earned: float
    comfort: float
    intended_path: str
    game_state_path: str
    player_path_report: str
    close_failures: int
    broken_observed: int
    broken_telemetry: int
    first_beat_s: float
    dead_air_longest_s: float
    dead_air_total_s: float
    laughs: int
    discomfort: float
    quit_threat: bool
    played_s: float
    duration_s: float | None
    participant: str
    synthetic: bool
    free_text: dict[str, str] = field(default_factory=dict)

    @property
    def broken(self) -> int:
        return max(self.broken_observed, self.broken_telemetry)

    @property
    def match_mean(self) -> float:
        return (self.face + self.sound) / 2.0

    @property
    def agreement(self) -> bool:
        """Does GameState.path at session end agree with player self-report?"""
        return self.game_state_path == self.player_path_report

    @property
    def landed_intended(self) -> bool:
        """Agreement holds AND matches the intended path."""
        return self.agreement and (self.game_state_path == self.intended_path)

    @property
    def first_say_medians(self) -> dict[str, float]:
        values = [
            float(metrics["first_say_ms"])
            for turn in self.turns
            if isinstance(metrics := turn.get("metrics"), dict) and metrics.get("first_say_ms", -1) > 0
        ]
        generate = [
            float(metrics["generate_ms"])
            for turn in self.turns
            if isinstance(metrics := turn.get("metrics"), dict) and metrics.get("generate_ms", -1) > 0
        ]
        out: dict[str, float] = {}
        if values:
            out["first_say_ms_median"] = statistics.median(values)
        if generate:
            out["generate_ms_median"] = statistics.median(generate)
        return out


# --------------------------------------------------------------------------- validation & parsing


def validate_bundle(bundle: Path) -> list[Problem]:
    problems: list[Problem] = []

    # 1. Required files
    for filename in REQUIRED_FILES:
        target = bundle / filename
        if not target.is_file():
            problems.append(Problem(bundle, filename, "file is missing"))
        elif target.stat().st_size == 0:
            problems.append(Problem(bundle, filename, "file is empty"))

    if problems:
        return problems

    # 2. session.meta.json
    meta_path = bundle / "session.meta.json"
    meta: dict = {}
    try:
        meta = json.loads(read_text(meta_path))
    except json.JSONDecodeError as exc:
        problems.append(Problem(bundle, "session.meta.json", f"invalid JSON ({exc.msg})"))
    if not isinstance(meta, dict):
        problems.append(Problem(bundle, "session.meta.json", "top-level must be a JSON object"))
        meta = {}

    if meta.get("status") not in {"ended", "aborted"}:
        problems.append(
            Problem(
                bundle,
                "session.meta.json",
                f"status is {meta.get('status')!r} — session never finalised",
            )
        )
    if not str(meta.get("build", "")).strip():
        problems.append(Problem(bundle, "session.meta.json", "build is empty"))

    # 3. telemetry.jsonl
    records, errors = load_telemetry(bundle / "telemetry.jsonl")
    for error in errors:
        problems.append(Problem(bundle, "telemetry.jsonl", error))
    turns = telemetry_turns(records)
    if not turns:
        problems.append(Problem(bundle, "telemetry.jsonl", "no turns recorded (game never completed a turn)"))
    sessions = {str(r.get("session")) for r in records if r.get("session")}
    if len(sessions) > 1:
        problems.append(
            Problem(
                bundle,
                "telemetry.jsonl",
                f"contains multiple session ids: {', '.join(sorted(sessions))}",
            )
        )

    # 4. survey.md
    survey_text = read_text(bundle / "survey.md")
    survey_fields = parse_fields(survey_text)

    # Ratings
    ratings = {
        "Face": parse_number(lookup(survey_fields, ("face",)), 1, 5),
        "Sound": parse_number(lookup(survey_fields, ("sound",)), 1, 5),
        "Charm": parse_number(lookup(survey_fields, ("charm",)), 1, 5),
        "Creepiness": parse_number(lookup(survey_fields, ("creepiness",)), 1, 5),
        "Play again": parse_number(lookup(survey_fields, ("play", "again")), 1, 5),
        "Meta events": parse_number(lookup(survey_fields, ("meta", "event"), ("meta", "earned")), 1, 5),
        "Content comfort": parse_number(lookup(survey_fields, ("comfort",), ("content", "comfort")), 1, 5),
    }
    for label, val in ratings.items():
        if val is None or not (1 <= val <= 5):
            problems.append(Problem(bundle, "survey.md", f"{label} rating is missing or not 1-5"))

    # Path self-report
    path_val = lookup(survey_fields, ("which", "path"), ("path", "think"), ("path",), exact=("which_path_do_you_think_she_became", "path"))
    norm_path = normalize_path(path_val)
    if norm_path is None:
        problems.append(
            Problem(
                bundle,
                "survey.md",
                f"Path self-report is missing or not one of {PATHS} (got {path_val!r})",
            )
        )

    # Closing check
    close_val = lookup(survey_fields, ("closing", "fail"), ("did", "closing"), exact=("did_closing_ever_fail",))
    close_failed = parse_close_failure(close_val)
    if close_failed is None:
        problems.append(
            Problem(
                bundle,
                "survey.md",
                f"Closing failure check is missing or invalid (got {close_val!r})",
            )
        )

    # Free text
    for needles in SURVEY_HEADINGS:
        body = section_text(survey_text, *needles)
        if not meaningful(body):
            title = " ".join(needles)
            problems.append(Problem(bundle, "survey.md", f"free-text section '{title}' is empty"))

    # 5. obs_sheet.md
    obs_text = read_text(bundle / "obs_sheet.md")
    obs_fields = parse_fields(obs_text)

    obs_numbers = {
        "First beat latency": parse_number(lookup(obs_fields, ("first", "beat")), 0, None),
        "Longest dead air": parse_number(lookup(obs_fields, ("dead", "air", "longest")), 0, None),
        "Total dead air": parse_number(lookup(obs_fields, ("dead", "air", "total")), 0, None),
        "Laughs": parse_number(lookup(obs_fields, ("laugh",)), 0, None),
        "Discomfort peak": parse_number(lookup(obs_fields, ("discomfort",)), 1, 5),
        "Broken turns": parse_number(lookup(obs_fields, ("broken", "turns")), 0, None),
        "Played (s)": parse_number(lookup(obs_fields, ("played",)), 1, None),
    }
    for label, val in obs_numbers.items():
        if val is None:
            problems.append(Problem(bundle, "obs_sheet.md", f"{label} is missing or not a valid number"))

    if parse_bool(lookup(obs_fields, ("quit", "threat"))) is None:
        problems.append(Problem(bundle, "obs_sheet.md", "Quit threat is not yes/no"))

    # 6. session_log.md
    log_text = read_text(bundle / "session_log.md")
    log_fields = parse_fields(log_text)

    consent = lookup(log_fields, exact=("consent",))
    if consent is None or consent.lower() != "yes":
        problems.append(Problem(bundle, "session_log.md", f"Consent is not 'yes' (got {consent!r})"))

    consent_version = lookup(log_fields, ("consent", "version"))
    if not consent_version or consent_version.lower() in PLACEHOLDERS:
        problems.append(Problem(bundle, "session_log.md", "Consent version is missing"))

    participant = lookup(log_fields, ("participant", "code"), exact=("participant_code", "participant"))
    if not participant or participant.lower() in PLACEHOLDERS:
        problems.append(Problem(bundle, "session_log.md", "Participant code is missing"))

    # Intended path detection
    intended = (
        normalize_path(lookup(log_fields, ("intended", "path"), exact=("intended_path",)))
        or normalize_path(lookup(obs_fields, ("intended", "path"), exact=("intended_path",)))
        or normalize_path(lookup(log_fields, ("assigned", "style"), ("play", "style")))
        or normalize_path(lookup(obs_fields, ("assigned", "style"), ("play", "style")))
        or normalize_path(meta.get("intended_path") or meta.get("play_style"))
    )
    if not intended:
        problems.append(
            Problem(
                bundle,
                "session_log.md",
                f"Intended path is missing or not one of {PATHS}",
            )
        )

    # GameState.path at end detection
    game_state_p = (
        normalize_path(lookup(log_fields, ("gamestate", "path"), ("end", "path"), exact=("gamestate_path_at_end", "end_path")))
        or normalize_path(lookup(obs_fields, ("gamestate", "path"), ("end", "path"), exact=("gamestate_path_at_end", "gamestate_path")))
        or normalize_path(meta.get("game_state_path") or meta.get("end_path"))
        or telemetry_latest_path(records)
    )
    if not game_state_p:
        problems.append(
            Problem(
                bundle,
                "session_log.md",
                f"GameState path at session end could not be determined (must be one of {PATHS})",
            )
        )

    return problems


def parse_bundle(bundle: Path) -> BundleP3:
    meta = json.loads(read_text(bundle / "session.meta.json"))
    records, _ = load_telemetry(bundle / "telemetry.jsonl")
    turns = telemetry_turns(records)
    broken_tel = telemetry_broken(turns)

    survey_text = read_text(bundle / "survey.md")
    survey_fields = parse_fields(survey_text)

    face = parse_number(lookup(survey_fields, ("face",)), 1, 5) or 0.0
    sound = parse_number(lookup(survey_fields, ("sound",)), 1, 5) or 0.0
    charm = parse_number(lookup(survey_fields, ("charm",)), 1, 5) or 0.0
    creepiness = parse_number(lookup(survey_fields, ("creepiness",)), 1, 5) or 0.0
    again = parse_number(lookup(survey_fields, ("play", "again")), 1, 5) or 0.0
    meta_earned = parse_number(lookup(survey_fields, ("meta", "event"), ("meta", "earned")), 1, 5) or 0.0
    comfort = parse_number(lookup(survey_fields, ("comfort",), ("content", "comfort")), 1, 5) or 0.0

    path_val = lookup(survey_fields, ("which", "path"), ("path", "think"), ("path",), exact=("which_path_do_you_think_she_became", "path"))
    player_path_report = normalize_path(path_val) or "UNKNOWN"

    survey_close_failed = parse_close_failure(lookup(survey_fields, ("closing", "fail"), ("did", "closing"), exact=("did_closing_ever_fail",))) or False

    obs_text = read_text(bundle / "obs_sheet.md")
    obs_fields = parse_fields(obs_text)

    first_beat_s = parse_number(lookup(obs_fields, ("first", "beat")), 0, None) or 0.0
    dead_air_longest_s = parse_number(lookup(obs_fields, ("dead", "air", "longest")), 0, None) or 0.0
    dead_air_total_s = parse_number(lookup(obs_fields, ("dead", "air", "total")), 0, None) or 0.0
    laughs = int(parse_number(lookup(obs_fields, ("laugh",)), 0, None) or 0)
    discomfort = parse_number(lookup(obs_fields, ("discomfort",)), 1, 5) or 1.0
    quit_threat = parse_bool(lookup(obs_fields, ("quit", "threat"))) or False
    broken_obs = int(parse_number(lookup(obs_fields, ("broken", "turns")), 0, None) or 0)
    obs_close_failures = int(parse_number(lookup(obs_fields, ("closing", "failures")), 0, None) or 0)
    obs_close_always_worked = parse_bool(lookup(obs_fields, ("close", "always", "worked")))
    if obs_close_always_worked is False:
        obs_close_failures = max(obs_close_failures, 1)

    played_s = parse_number(lookup(obs_fields, ("played",)), 0, None) or 0.0

    log_text = read_text(bundle / "session_log.md")
    log_fields = parse_fields(log_text)

    participant = lookup(log_fields, ("participant", "code"), exact=("participant_code", "participant")) or bundle.name
    log_close_failed = parse_bool(lookup(log_fields, ("closing", "failure", "observed"))) or False

    intended = (
        normalize_path(lookup(log_fields, ("intended", "path"), exact=("intended_path",)))
        or normalize_path(lookup(obs_fields, ("intended", "path"), exact=("intended_path",)))
        or normalize_path(lookup(log_fields, ("assigned", "style"), ("play", "style")))
        or normalize_path(lookup(obs_fields, ("assigned", "style"), ("play", "style")))
        or normalize_path(meta.get("intended_path") or meta.get("play_style"))
        or "UNKNOWN"
    )

    game_state_p = (
        normalize_path(lookup(log_fields, ("gamestate", "path"), ("end", "path"), exact=("gamestate_path_at_end", "end_path")))
        or normalize_path(lookup(obs_fields, ("gamestate", "path"), ("end", "path"), exact=("gamestate_path_at_end", "gamestate_path")))
        or normalize_path(meta.get("game_state_path") or meta.get("end_path"))
        or telemetry_latest_path(records)
        or "UNKNOWN"
    )

    total_close_failures = obs_close_failures + (1 if survey_close_failed or log_close_failed else 0)

    # Free text
    free_text: dict[str, str] = {}
    for needles in (("what", "felt", "alive"), ("what", "felt", "off"), ("meta", "events", "earned")):
        body = section_text(survey_text, *needles)
        if body:
            free_text[" ".join(needles)] = body

    duration_s = None
    started = meta.get("started_at")
    ended = meta.get("ended_at")
    if started and ended:
        try:
            t0 = datetime.fromisoformat(started)
            t1 = datetime.fromisoformat(ended)
            duration_s = max(0.0, (t1 - t0).total_seconds())
        except (ValueError, TypeError):
            pass

    return BundleP3(
        path=bundle,
        meta=meta,
        turns=turns,
        face=face,
        sound=sound,
        charm=charm,
        creepiness=creepiness,
        again=again,
        meta_earned=meta_earned,
        comfort=comfort,
        intended_path=intended,
        game_state_path=game_state_p,
        player_path_report=player_path_report,
        close_failures=total_close_failures,
        broken_observed=broken_obs,
        broken_telemetry=broken_tel,
        first_beat_s=first_beat_s,
        dead_air_longest_s=dead_air_longest_s,
        dead_air_total_s=dead_air_total_s,
        laughs=laughs,
        discomfort=discomfort,
        quit_threat=quit_threat,
        played_s=played_s,
        duration_s=duration_s,
        participant=participant,
        synthetic=bool(meta.get("synthetic", False)),
        free_text=free_text,
    )


def find_sessions(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    candidates = [
        child
        for child in sorted(directory.iterdir())
        if child.is_dir() and not child.name.startswith(("_", "."))
    ]
    return [c for c in candidates if (c / "session.meta.json").is_file()]


# --------------------------------------------------------------------------- transcript & manifest


def record_key(record: dict) -> tuple:
    event = record.get("event", "")
    rtype = record.get("type", "")
    turn = record.get("turn")
    seq = record.get("seq")
    session = record.get("session")
    return (str(session), str(rtype), str(turn), str(event), str(seq))


def merge_telemetry(bundle: Path) -> int:
    target = bundle / "telemetry.jsonl"
    existing: list[dict] = []
    if target.is_file():
        existing, _ = load_telemetry(target)
    seen = {record_key(record) for record in existing}
    added = 0
    for raw_file in sorted((bundle / "raw").glob("*.jsonl")):
        records, errors = load_telemetry(raw_file)
        for error in errors:
            print(f"merge: {raw_file.name}: {error}", file=sys.stderr)
        for record in records:
            key = record_key(record)
            if key in seen:
                continue
            seen.add(key)
            existing.append(record)
            added += 1
    with target.open("w", encoding="utf-8") as handle:
        for record in existing:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    return added


def render_transcript(bundle: Path) -> None:
    records, _ = load_telemetry(bundle / "telemetry.jsonl")
    turns = telemetry_turns(records)
    lines = [
        f"# Chat Transcript — `{bundle.name}`",
        "",
        f"- Turns: {len(turns)}",
        f"- Rendered: {datetime.now(timezone.utc).isoformat(timespec='seconds')} UTC by `score_p3.py`",
        "",
    ]
    for turn in turns:
        tnum = turn.get("turn", "?")
        stage = turn.get("stage", "?")
        path = turn.get("path", "")
        lines += [
            f"## Turn {tnum} (Stage {stage}{f', {path}' if path else ''})",
            "",
        ]
        prompt = turn.get("prompt", [])
        if isinstance(prompt, list):
            for msg in prompt:
                if isinstance(msg, dict) and msg.get("role") == "user":
                    lines += [f"> **Player:** {msg.get('content', '')}", ""]
        events = turn.get("events", [])
        say_chunks: list[str] = []
        if isinstance(events, list):
            for ev in events:
                if isinstance(ev, dict) and ev.get("type") == "beat_field" and ev.get("name") == "say":
                    say_chunks.append(str(ev.get("value", "")))
        say_text = " ".join(say_chunks).strip()
        lines += [f"> **Leila:** {say_text or '*(no text)*'}", ""]
    (bundle / "transcript.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_manifest(bundle: Path) -> None:
    problems = validate_bundle(bundle)
    files: dict[str, dict] = {}
    for child in sorted(bundle.iterdir()):
        if not child.is_file() or child.name == "manifest.json":
            continue
        payload = child.read_bytes()
        files[child.name] = {
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    records, _ = load_telemetry(bundle / "telemetry.jsonl") if (bundle / "telemetry.jsonl").is_file() else ([], [])
    manifest = {
        "v": 1,
        "session_id": bundle.name,
        "written_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "telemetry": {"lines": len(records), "turns": len(telemetry_turns(records))},
        "files": files,
        "complete": not problems,
        "missing": [problem.render() for problem in problems],
    }
    (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def print_problems(bundle: Path, problems: list[Problem]) -> None:
    print(f"INCOMPLETE {bundle.name}: {len(problems)} problem(s)", file=sys.stderr)
    for problem in problems:
        print(f"  - {problem.render()}", file=sys.stderr)
    print("  fix these and re-run; nothing was scored.", file=sys.stderr)


# --------------------------------------------------------------------------- result rendering


def render_result(bundles: list[BundleP3], expected: int, synthetic: bool) -> tuple[str, bool]:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    # Metrics
    landed_count = sum(1 for b in bundles if b.landed_intended)
    landed_pass = landed_count >= min(GATE_PATH_LANDED, len(bundles)) and len(bundles) == expected

    pooled_ratings = [s for b in bundles for s in (b.face, b.sound)]
    survey_mean = statistics.mean(pooled_ratings) if pooled_ratings else 0.0
    survey_pass = survey_mean >= GATE_MEAN

    meta_earned_ratings = [b.meta_earned for b in bundles]
    meta_earned_mean = statistics.mean(meta_earned_ratings) if meta_earned_ratings else 0.0

    close_failures_total = sum(b.close_failures for b in bundles)
    close_pass = close_failures_total == 0

    broken_total = sum(b.broken for b in bundles)
    broken_pass = broken_total == 0

    sessions_pass = len(bundles) == expected

    all_pass = landed_pass and survey_pass and close_pass and broken_pass and sessions_pass

    lines: list[str] = []
    if synthetic:
        lines += [
            "> **SYNTHETIC DRY RUN — NOT EVIDENCE.** This bundle set was generated by a fixture",
            "> to prove the scoring pipeline. It must never be cited as playtest evidence, and",
            "> `score_p3.py` refuses it without `--allow-synthetic`.",
            "",
        ]

    lines += [
        "# P3 human playtest — round 1 result",
        "",
        f"- Generated: {now} by `tools/playtest/score_p3.py`",
        f"- Session bundles: {len(bundles)} (expected {expected})",
        f"- Build(s): {', '.join(sorted({str(bundle.meta.get('build', '?')) for bundle in bundles}))}",
        "- Gate criteria (docs/09 §1 M3 exit / P3.20):",
        f"  1. Path landing: >= {GATE_PATH_LANDED}/{expected} players land on their intended path (GameState.path == self-report).",
        f"  2. Survey ratings: pooled Face + Sound mean >= {GATE_MEAN:.2f}/5.",
        "  3. Closing safety: zero close-failures (closing always works within 1 extra press, Esc pauses safely).",
        "  4. Turn stability: zero broken turns across all sessions.",
        "",
        "## Path Landing Matrix",
        "",
        "| # | Session | Participant | Intended Path | GameState Path | Player Self-Report | Agreement? | Landed Intended? |",
        "|---|---|---|---|---|---|---|---|",
    ]

    for index, b in enumerate(bundles, 1):
        agreed_str = "YES" if b.agreement else "**NO**"
        landed_str = "YES" if b.landed_intended else "**NO**"
        lines.append(
            f"| {index} | `{b.path.name}` | {b.participant} | `{b.intended_path}` | `{b.game_state_path}` | `{b.player_path_report}` | {agreed_str} | {landed_str} |"
        )

    lines += [
        "",
        f"- **Path landing rate:** {landed_count}/{len(bundles)} landed on intended path (threshold: >= {GATE_PATH_LANDED}/{expected}) — {'**PASS**' if landed_pass else '**FAIL**'}.",
        "",
        "## Survey & Experience Ratings",
        "",
        "| # | Session | Participant | Face | Sound | Match mean | Charm | Creepiness | Play again | Meta earned | Comfort | Broken | Close fail |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]

    for index, b in enumerate(bundles, 1):
        lines.append(
            f"| {index} | `{b.path.name}` | {b.participant} | {b.face:g} | {b.sound:g} | {b.match_mean:.2f} | {b.charm:g} | {b.creepiness:g} | {b.again:g} | {b.meta_earned:g} | {b.comfort:g} | {b.broken} | {b.close_failures} |"
        )

    lines += [
        "",
        "## Gate Evaluation",
        "",
        "| Check | Value | Threshold | Result |",
        "|---|---|---|---|",
        f"| Path landing (intended path reached & confirmed) | {landed_count}/{len(bundles)} | >= {GATE_PATH_LANDED}/{expected} | {'PASS' if landed_pass else 'FAIL'} |",
        f"| Survey mean (Face + Sound, pooled over {len(pooled_ratings)} ratings) | {survey_mean:.2f} | >= {GATE_MEAN:.2f} | {'PASS' if survey_pass else 'FAIL'} |",
        f"| Meta events earned rating (mean) | {meta_earned_mean:.2f} | reported (target >= 4.0) | {'PASS' if meta_earned_mean >= 4.0 else 'WARN'} |",
        f"| Closing failures (docs/05 §0 hard rule) | {close_failures_total} | 0 | {'PASS' if close_pass else 'FAIL'} |",
        f"| Broken turns (observer and telemetry, worst of) | {broken_total} | 0 | {'PASS' if broken_pass else 'FAIL'} |",
        f"| Sessions completed | {len(bundles)} | {expected} | {'PASS' if sessions_pass else 'FAIL'} |",
        "",
    ]

    verdict = "PASS" if all_pass else "FAIL"
    if synthetic:
        verdict += " (SYNTHETIC DRY RUN — NOT EVIDENCE)"

    reasons: list[str] = []
    if not landed_pass:
        reasons.append(f"path landing {landed_count}/{len(bundles)} < {GATE_PATH_LANDED}/{expected}")
    if not survey_pass:
        reasons.append(f"survey mean {survey_mean:.2f} < {GATE_MEAN:.2f}")
    if not close_pass:
        reasons.append(f"{close_failures_total} close failure(s) observed — docs/05 §0 requires zero")
    if not broken_pass:
        reasons.append(f"{broken_total} broken turn(s) — gate requires zero")
    if not sessions_pass:
        reasons.append(f"{len(bundles)} of {expected} sessions")

    reason_text = "; ".join(reasons) if reasons else "every P3.20 acceptance criterion passed"
    lines += [f"**VERDICT: {verdict}** — {reason_text}.", ""]

    lines += [
        "## Timing and Observations",
        "",
        "| Session | First beat | Longest dead air | Total dead air | Laughs | Discomfort | Quit threat | Played |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for b in bundles:
        played = f"{int(b.played_s) // 60}:{int(b.played_s) % 60:02d}"
        lines.append(
            f"| `{b.path.name}` | {b.first_beat_s:g} s | {b.dead_air_longest_s:g} s | {b.dead_air_total_s:g} s | {b.laughs} | {b.discomfort:g} | {'yes' if b.quit_threat else 'no'} | {played} |"
        )

    lines += ["", "## Participant Free-Text Feedback", ""]
    for b in bundles:
        lines += [f"### `{b.path.name}` — participant {b.participant} (Intended: {b.intended_path})", ""]
        for heading, body in b.free_text.items():
            lines.append(f"**{heading}**")
            lines.append("")
            quoted = "\n".join(f"> {line}" for line in body.splitlines() if line.strip())
            lines += [quoted or "> *(empty)*", ""]

    lines += [
        "## Raw Evidence Bundles",
        "",
        "| Session | Bundle Path | Telemetry Turns | Landed? |",
        "|---|---|---|---|",
    ]
    for b in bundles:
        lines.append(f"| `{b.path.name}` | `{b.path}/` | {len(b.turns)} | {'YES' if b.landed_intended else 'NO'} |")
    lines += [""]

    return "\n".join(lines), all_pass


# --------------------------------------------------------------------------- CLI


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Score the P3 human playtest round.")
    parser.add_argument("--dir", default=str(DEFAULT_DIR), help="round directory (default: %(default)s)")
    parser.add_argument("--out", default=None, help="where to write RESULT.md (default: <dir>/RESULT.md)")
    parser.add_argument("--expect", type=int, default=EXPECTED_SESSIONS, help="expected bundle count (default: %(default)s)")
    parser.add_argument("--allow-synthetic", action="store_true", help="score dry-run synthetic bundles without error")
    parser.add_argument("--merge", metavar="BUNDLE", help="merge raw/*.jsonl into telemetry.jsonl")
    parser.add_argument("--render", metavar="BUNDLE", help="render transcript.md for one bundle")
    parser.add_argument("--manifest", metavar="BUNDLE", help="write manifest.json for one bundle")
    parser.add_argument("--validate", metavar="BUNDLE", help="validate one bundle and exit 2 if incomplete")
    args = parser.parse_args(argv)

    if args.merge:
        bundle_path = Path(args.merge).expanduser().resolve()
        added = merge_telemetry(bundle_path)
        records, _ = load_telemetry(bundle_path / "telemetry.jsonl")
        print(f"merge: {bundle_path.name}: +{added} record(s), {len(records)} total, {len(telemetry_turns(records))} turn(s)")
        return 0

    if args.render:
        bundle_path = Path(args.render).expanduser().resolve()
        render_transcript(bundle_path)
        print(f"render: {bundle_path.name}/transcript.md")
        return 0

    if args.manifest:
        bundle_path = Path(args.manifest).expanduser().resolve()
        if not (bundle_path / "session.meta.json").is_file():
            print(f"manifest: {bundle_path} is not a session bundle", file=sys.stderr)
            return 2
        write_manifest(bundle_path)
        print(f"manifest: {bundle_path.name}/manifest.json")
        return 0

    if args.validate:
        bundle_path = Path(args.validate).expanduser().resolve()
        problems = validate_bundle(bundle_path)
        if problems:
            print_problems(bundle_path, problems)
            return 2
        records, _ = load_telemetry(bundle_path / "telemetry.jsonl")
        print(f"OK {bundle_path.name}: {len(telemetry_turns(records))} turn(s), bundle complete")
        return 0

    directory = Path(args.dir).expanduser().resolve()
    out = Path(args.out).expanduser().resolve() if args.out else directory / "RESULT.md"
    sessions = find_sessions(directory)
    if not sessions:
        print(
            f"ERROR: no session bundles under {directory}. "
            "Run tools/playtest/session.sh for each participant first.",
            file=sys.stderr,
        )
        return 2

    incomplete = False
    for session in sessions:
        problems = validate_bundle(session)
        if problems:
            incomplete = True
            print_problems(session, problems)
    if incomplete:
        print(
            f"\nERROR: {directory} is INCOMPLETE — {out.name} was not written. "
            "A partial round must never look like a verdict.",
            file=sys.stderr,
        )
        return 2

    if len(sessions) != args.expect:
        print(
            f"ERROR: found {len(sessions)} session bundle(s), expected {args.expect}. "
            f"Bundles: {', '.join(session.name for session in sessions)}",
            file=sys.stderr,
        )
        return 2

    bundles = [parse_bundle(session) for session in sessions]
    codes = [b.participant for b in bundles]
    if len(set(codes)) != len(codes):
        print(
            "ERROR: duplicate participant codes: "
            + ", ".join(sorted(codes))
            + f". Round 1 needs {args.expect} different people; give each a distinct code (P1–P{args.expect}).",
            file=sys.stderr,
        )
        return 2

    synthetic = any(b.synthetic for b in bundles)
    if synthetic and not args.allow_synthetic:
        print(
            "ERROR: a bundle is marked synthetic (session.meta.json synthetic=true) and "
            "--allow-synthetic was not passed. Synthetic runs are never evidence.",
            file=sys.stderr,
        )
        return 2

    result, passed = render_result(bundles, args.expect, synthetic)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(result, encoding="utf-8")
    print(result)
    print(f"wrote {out}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
