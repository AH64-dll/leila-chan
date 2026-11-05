#!/usr/bin/env python3
"""Score the P2 human playtest round (docs/09 §1 M1 exit criterion 1).

Reads the human session bundles under ``production/playtests/P2/human/`` and writes
``RESULT.md`` with the face/sound survey verdict and the broken-turn count that the M1 exit
requires:

    a stranger plays 10 minutes, the face/sound match her words (survey mean >= 4/5),
    zero broken turns

A *session bundle* is one directory holding:

    session.meta.json   written by tools/playtest/session.sh
    telemetry.jsonl     the game's own transcript (JSONL, one record per turn)
    survey.md           filled by the participant
    obs_sheet.md        filled by the observer
    session_log.md      filled by the facilitator

The tool is deliberately strict. A missing file, an unfilled rating, a missing consent row or a
transcript with no turn is an incomplete bundle: it prints what is missing and exits 2 without
writing RESULT.md, because a partial round must never look like a verdict.

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
EXPECTED_SESSIONS = 3
SURVEY_HEADINGS = (("what", "felt", "alive"), ("what", "felt", "off"))
REQUIRED_FILES = (
    "session.meta.json",
    "telemetry.jsonl",
    "survey.md",
    "obs_sheet.md",
    "session_log.md",
)
PLACEHOLDERS = {"", "—", "-", "–", "?", "??", "...", "n/a", "na", "tbd", "todo", "xxx"}

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "production" / "playtests" / "P2" / "human"

KV_ROW = re.compile(r"^\|\s*(?P<key>[^|]+?)\s*\|\s*(?P<value>[^|]*?)\s*\|\s*$")
HEADING = re.compile(r"^#{2,3}\s+(?P<title>.*)$")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


# --------------------------------------------------------------------------- parsing


def normalize_key(label: str) -> str:
    """`First beat latency (s)` -> `first_beat_latency_s`."""
    return re.sub(r"[^a-z0-9]+", "_", label.strip().lower()).strip("_")


def parse_fields(text: str) -> dict[str, str]:
    """Every `| Field | value |` row of a markdown document, keyed by normalized label.

    Two-column rows only: the per-turn observation table has six columns and is therefore
    ignored, while the summary tables (three to five columns would be a mistake) parse. The
    first occurrence wins, so a header row repeated lower in the file cannot shadow a value.
    """
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


def lookup(fields: dict[str, str], *needles: tuple[str, ...], exact: tuple[str, ...] = ()) -> str | None:
    """Find a filled value by exact key first, then by 'all these words in the key'."""
    for candidate in exact:
        if candidate in fields:
            return fields[candidate]
    for needle in needles:
        # A bare string is one needle; a tuple means "all of these words". Treating a
        # string as a sequence would match a key that merely contains its letters.
        parts = (needle,) if isinstance(needle, str) else tuple(needle)
        for key, value in fields.items():
            if all(part in key for part in parts):
                return value
    return None


def parse_number(raw: str | None, low: float | None = None, high: float | None = None) -> float | None:
    """The first number in a human's cell, or None when the cell is a placeholder/garbage."""
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


def section_text(text: str, *needles: str) -> str:
    """Markdown body under the first `##`/`###` heading containing every needle."""
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


# --------------------------------------------------------------------------- bundle model


@dataclass
class Problem:
    path: Path
    source: str
    message: str

    def render(self) -> str:
        return f"{self.path.name}: {self.source}: {self.message}"


@dataclass
class Bundle:
    path: Path
    meta: dict
    turns: list[dict]
    face: float
    sound: float
    charm: float
    creepiness: float
    again: float
    first_beat_s: float
    dead_air_longest_s: float
    dead_air_total_s: float
    laughs: int
    discomfort: float
    quit_threat: bool
    broken_observed: int
    broken_telemetry: int
    played_s: float
    duration_s: float | None
    participant: str
    synthetic: bool
    free_text: dict[str, str] = field(default_factory=dict)

    @property
    def broken(self) -> int:
        """Conservative: a visible break the observer missed still counts."""
        return max(self.broken_observed, self.broken_telemetry)

    @property
    def match_mean(self) -> float:
        return (self.face + self.sound) / 2.0

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
        status = str(meta.get("status", "completed"))
        if status != "completed" or turn.get("error"):
            broken += 1
    return broken


def record_key(record: dict) -> tuple:
    return (
        str(record.get("session", "")),
        str(record.get("type", "")),
        record.get("turn"),
        str(record.get("event", "")),
        record.get("seq"),
    )


# --------------------------------------------------------------------------- validation


def validate_bundle(path: Path) -> list[Problem]:
    """Every reason this bundle cannot count as evidence. Empty list == complete."""
    problems: list[Problem] = []

    def problem(source: str, message: str) -> None:
        problems.append(Problem(path, source, message))

    for name in REQUIRED_FILES:
        if not (path / name).is_file():
            problem(name, "missing")

    meta_path = path / "session.meta.json"
    meta: dict = {}
    if meta_path.is_file():
        try:
            meta = json.loads(read_text(meta_path))
        except json.JSONDecodeError as exc:
            problem("session.meta.json", f"invalid JSON: {exc.msg}")
            meta = {}
    if meta:
        for key in ("session_id", "started_at", "ended_at", "build", "status"):
            if not str(meta.get(key, "")).strip():
                problem("session.meta.json", f"{key} is empty")
        if str(meta.get("status", "")) != "ended":
            problem("session.meta.json", f"status is {meta.get('status')!r}, expected 'ended'")

    telemetry_path = path / "telemetry.jsonl"
    if telemetry_path.is_file():
        records, errors = load_telemetry(telemetry_path)
        for error in errors[:5]:
            problem("telemetry.jsonl", f"unparseable {error}")
        turns = telemetry_turns(records)
        if not turns:
            problem(
                "telemetry.jsonl",
                "0 turn records (server down, or a release export: transcripts are dev-only)",
            )
        sessions = {str(record.get("session", "")) for record in records if record.get("session")}
        if len(sessions) > 1:
            problem("telemetry.jsonl", f"{len(sessions)} transcript sessions in one bundle")

    survey_path = path / "survey.md"
    if survey_path.is_file():
        survey = parse_fields(read_text(survey_path))
        for label, needles, exact in (
            ("Face", ("face",), ("face",)),
            ("Sound", ("sound",), ("sound",)),
            ("Charm", ("charm",), ("charm",)),
            ("Creepiness", ("creepiness",), ("creepiness",)),
            (
                "Play again",
                ("play", "again"),
                ("play_again", "would_play_again", "again"),
            ),
        ):
            if parse_number(lookup(survey, *needles, exact=exact), 1, 5) is None:
                problem("survey.md", f"{label} rating is missing or not 1-5")
        text = read_text(survey_path)
        for heading in SURVEY_HEADINGS:
            if not meaningful(section_text(text, *heading)):
                problem("survey.md", f"'## {' '.join(heading).capitalize()}' answer is empty")

    obs_path = path / "obs_sheet.md"
    if obs_path.is_file():
        obs = parse_fields(read_text(obs_path))
        numeric = (
            ("First beat latency", ("first", "beat"), None),
            ("Dead air, longest", ("dead", "air", "longest"), 0),
            ("Dead air, total", ("dead", "air", "total"), 0),
            ("Laughs", ("laughs",), 0),
            ("Discomfort, peak", ("discomfort",), (1, 5)),
            ("Broken turns", ("broken",), 0),
            ("Played", ("played",), 0),
        )
        for label, needles, bounds in numeric:
            raw = lookup(obs, needles)
            if bounds is None:
                ok = parse_number(raw, 0) is not None
            elif isinstance(bounds, tuple):
                ok = parse_number(raw, *bounds) is not None
            else:
                ok = parse_number(raw, bounds) is not None
            if not ok:
                problem("obs_sheet.md", f"{label} is missing or not a number")
        if parse_bool(lookup(obs, ("quit", "threat"))) is None:
            problem("obs_sheet.md", "Quit threat is missing (yes/no)")

    log_path = path / "session_log.md"
    if log_path.is_file():
        log = parse_fields(read_text(log_path))
        for label, needles in (
            ("Participant code", ("participant",)),
            ("Consent version", ("consent", "version")),
            ("Date", ("date",)),
            ("Started", ("started",)),
            ("Ended", ("ended",)),
            ("Build", ("build",)),
            ("Facilitator", ("facilitator",)),
        ):
            raw = lookup(log, needles)
            if raw is None or not meaningful(raw):
                problem("session_log.md", f"{label} is missing")
        participant = lookup(log, ("participant",))
        if participant and " " in participant.strip():
            problem("session_log.md", "Participant code contains a space (a code, not a name)")
        if parse_bool(lookup(log, ("consent",), exact=("consent",))) is not True:
            problem("session_log.md", "Consent is not 'yes'")

    return problems


def parse_bundle(path: Path) -> Bundle:
    meta = json.loads(read_text(path / "session.meta.json"))
    records, _ = load_telemetry(path / "telemetry.jsonl")
    turns = telemetry_turns(records)
    survey = parse_fields(read_text(path / "survey.md"))
    obs = parse_fields(read_text(path / "obs_sheet.md"))
    log = parse_fields(read_text(path / "session_log.md"))

    face = parse_number(lookup(survey, ("face",), exact=("face",)), 1, 5)
    sound = parse_number(lookup(survey, ("sound",), exact=("sound",)), 1, 5)
    charm = parse_number(lookup(survey, ("charm",), exact=("charm",)), 1, 5)
    creepiness = parse_number(lookup(survey, ("creepiness",), exact=("creepiness",)), 1, 5)
    again = parse_number(
        lookup(survey, ("play", "again"), exact=("play_again", "would_play_again", "again")), 1, 5
    )
    assert None not in (face, sound, charm, creepiness, again), "validated bundle has gaps"

    first_beat = parse_number(lookup(obs, ("first", "beat")), 0)
    dead_air_longest = parse_number(lookup(obs, ("dead", "air", "longest")), 0)
    dead_air_total = parse_number(lookup(obs, ("dead", "air", "total")), 0)
    laughs = parse_number(lookup(obs, ("laughs",)), 0)
    discomfort = parse_number(lookup(obs, ("discomfort",)), 1, 5)
    broken_observed = parse_number(lookup(obs, ("broken",)), 0)
    played_s = parse_number(lookup(obs, ("played",)), 0)
    assert None not in (
        first_beat,
        dead_air_longest,
        dead_air_total,
        laughs,
        discomfort,
        broken_observed,
        played_s,
    ), "validated bundle has gaps"

    started = _parse_time(meta.get("started_at"))
    ended = _parse_time(meta.get("ended_at"))
    duration = (ended - started).total_seconds() if started and ended else None

    text = read_text(path / "survey.md")
    free_text = {
        " ".join(heading).capitalize(): section_text(text, *heading) for heading in SURVEY_HEADINGS
    }

    return Bundle(
        path=path,
        meta=meta,
        turns=turns,
        face=face,
        sound=sound,
        charm=charm,
        creepiness=creepiness,
        again=again,
        first_beat_s=first_beat,
        dead_air_longest_s=dead_air_longest,
        dead_air_total_s=dead_air_total,
        laughs=int(laughs),
        discomfort=discomfort,
        quit_threat=bool(parse_bool(lookup(obs, ("quit", "threat")))),
        broken_observed=int(broken_observed),
        broken_telemetry=telemetry_broken(turns),
        played_s=played_s,
        duration_s=duration,
        participant=(lookup(log, ("participant",)) or "?").strip(),
        synthetic=bool(meta.get("synthetic")),
        free_text=free_text,
    )


def _parse_time(raw: object) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return None


def find_sessions(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(
        (child for child in directory.iterdir() if child.is_dir() and not child.name.startswith("_")),
        key=lambda child: child.name,
    )


# --------------------------------------------------------------------------- output


def render_transcript(path: Path) -> str:
    """Readable chat log from the bundle's own files — needs only meta + telemetry."""
    meta = json.loads(read_text(path / "session.meta.json"))
    records, _ = load_telemetry(path / "telemetry.jsonl")
    turns = telemetry_turns(records)
    log_path = path / "session_log.md"
    log = parse_fields(read_text(log_path)) if log_path.is_file() else {}
    participant = (lookup(log, ("participant",)) or "?").strip()
    lines = [
        f"# Transcript — {meta.get('session_id', path.name)}",
        "",
        f"- Participant: `{participant}` · turns: {len(turns)} "
        f"· broken (telemetry): {telemetry_broken(turns)}",
        f"- Build: {meta.get('build', '?')} · started: {meta.get('started_at', '?')} "
        f"· ended: {meta.get('ended_at', '?')}",
        "- Turn numbers are 1-based here; `telemetry.jsonl` keeps the 0-based `turn` index.",
        "",
    ]
    for turn in turns:
        raw_number = turn.get("turn", 0)
        number = int(raw_number) + 1 if isinstance(raw_number, int) else raw_number
        status = (turn.get("meta") or {}).get("status", "completed")
        metrics = turn.get("metrics") if isinstance(turn.get("metrics"), dict) else {}
        lines.append(f"## Turn {number}")
        lines.append("")
        player = player_line(turn)
        if player:
            lines.append(f"**Player:** {player}")
            lines.append("")
        beats = beat_rows(turn)
        if not beats:
            lines.append("*No beat was displayed.*")
            lines.append("")
        for index, beat in sorted(beats.items()):
            feeling = beat.get("feeling", "?")
            intensity = beat.get("intensity", "?")
            say = beat.get("say", "")
            if say:
                lines.append(f"- **{feeling}/{intensity}:** {say}")
        inner = field_value(turn, "inner")
        if inner:
            lines.append(f"- dev-only `inner`: {inner}")
        flags = [f"status={status}"]
        for key, label in (("first_say_ms", "first say"), ("generate_ms", "generated")):
            value = metrics.get(key)
            if isinstance(value, (int, float)) and value > 0:
                flags.append(f"{label} {value / 1000:.1f}s")
        lines.append("")
        lines.append("`" + " · ".join(flags) + "`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def player_line(turn: dict) -> str:
    prompt = turn.get("prompt")
    if not isinstance(prompt, list):
        return ""
    for message in reversed(prompt):
        if isinstance(message, dict) and message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, str):
                return content.strip()
    return ""


def beat_rows(turn: dict) -> dict[int, dict]:
    beats: dict[int, dict] = {}
    events = turn.get("events")
    if not isinstance(events, list):
        return beats
    for event in events:
        if not isinstance(event, dict) or event.get("type") != "beat_field":
            continue
        index = int(event.get("index", 0))
        beats.setdefault(index, {})[str(event.get("name", ""))] = event.get("value")
    return beats


def field_value(turn: dict, name: str) -> str:
    events = turn.get("events")
    if not isinstance(events, list):
        return ""
    for event in events:
        if isinstance(event, dict) and event.get("type") == "field" and event.get("name") == name:
            return str(event.get("value", ""))
    return ""


def display_path(path: Path) -> str:
    """Repo-relative when possible, absolute otherwise (tests score fixtures in tmp dirs)."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def render_result(bundles: list[Bundle], expected: int, synthetic: bool) -> tuple[str, bool]:
    """Return (RESULT.md text, passed)."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    faces = [bundle.face for bundle in bundles]
    sounds = [bundle.sound for bundle in bundles]
    pooled = faces + sounds
    survey_mean = statistics.fmean(pooled)
    broken_total = sum(bundle.broken for bundle in bundles)
    survey_pass = survey_mean >= GATE_MEAN
    broken_pass = broken_total == 0
    passed = survey_pass and broken_pass and len(bundles) == expected

    lines: list[str] = []
    if synthetic:
        lines += [
            "> **SYNTHETIC DRY RUN — NOT EVIDENCE.** This bundle was generated by a fixture under",
            "> `_dryrun/` to prove the scoring pipeline. It must never be cited as playtest evidence,",
            "> and `score.py` refuses it without `--allow-synthetic`.",
            "",
        ]
    lines += [
        "# P2 human playtest — round 1 result",
        "",
        f"- Generated: {now} by `tools/playtest/score.py`",
        f"- Session bundles: {len(bundles)} (expected {expected})",
        f"- Build(s): {', '.join(sorted({str(bundle.meta.get('build', '?')) for bundle in bundles}))}",
        "- Gate: docs/09 §1 M1 exit criterion 1 — a stranger plays ~10 minutes, the face/sound",
        f"  match her words (survey mean ≥ {GATE_MEAN:.2f}/5), zero broken turns.",
        "",
        "## Sessions",
        "",
        "| # | Session | Participant | Played | Turns | Face | Sound | Match mean | Charm "
        "| Creepiness | Play again | Broken (obs/tel) |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for index, bundle in enumerate(bundles, 1):
        played = f"{int(bundle.played_s) // 60}:{int(bundle.played_s) % 60:02d}"
        lines.append(
            f"| {index} | `{bundle.path.name}` | {bundle.participant} | {played} "
            f"| {len(bundle.turns)} | {bundle.face:g} | {bundle.sound:g} | {bundle.match_mean:.2f} "
            f"| {bundle.charm:g} | {bundle.creepiness:g} | {bundle.again:g} "
            f"| {bundle.broken_observed}/{bundle.broken_telemetry} |"
        )
    lines += [
        "",
        "## Gate",
        "",
        "| Check | Value | Threshold | Result |",
        "|---|---|---|---|",
        f"| Survey mean (Face + Sound, pooled over {len(pooled)} ratings) | "
        f"{survey_mean:.2f} | ≥ {GATE_MEAN:.2f} | {'PASS' if survey_pass else 'FAIL'} |",
        f"| Broken turns (observer and telemetry, worst of) | {broken_total} | 0 | "
        f"{'PASS' if broken_pass else 'FAIL'} |",
        f"| Sessions | {len(bundles)} | {expected} | "
        f"{'PASS' if len(bundles) == expected else 'FAIL'} |",
        "",
    ]
    verdict = "PASS" if passed else "FAIL"
    if synthetic:
        verdict += " (SYNTHETIC DRY RUN — NOT EVIDENCE)"
    reasons: list[str] = []
    if not survey_pass:
        reasons.append(f"survey mean {survey_mean:.2f} < {GATE_MEAN:.2f}")
    if not broken_pass:
        reasons.append(f"{broken_total} broken turn(s) — the M1 exit requires zero")
    if len(bundles) != expected:
        reasons.append(f"{len(bundles)} of {expected} sessions")
    reason_text = "; ".join(reasons) if reasons else "every M1 criterion 1 check passed"
    lines += [f"**VERDICT: {verdict}** — {reason_text}.", ""]

    lines += [
        "## Timing and other observations",
        "",
        "| Session | First beat (observer) | Longest dead air | Total dead air | Laughs "
        "| Discomfort peak | Quit threat | First `say` median (telemetry) |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for bundle in bundles:
        medians = bundle.first_say_medians
        first_say = (
            f"{medians['first_say_ms_median'] / 1000:.2f} s" if "first_say_ms_median" in medians else "—"
        )
        lines.append(
            f"| `{bundle.path.name}` | {bundle.first_beat_s:g} s | {bundle.dead_air_longest_s:g} s "
            f"| {bundle.dead_air_total_s:g} s | {bundle.laughs} | {bundle.discomfort:g} "
            f"| {'yes' if bundle.quit_threat else 'no'} | {first_say} |"
        )
    lines += ["", "## What they said", ""]
    for bundle in bundles:
        lines += [f"### `{bundle.path.name}` — participant {bundle.participant}", ""]
        for heading, body in bundle.free_text.items():
            lines.append(f"**{heading}**")
            lines.append("")
            quoted = "\n".join(f"> {line}" for line in body.splitlines() if line.strip())
            lines += [quoted or "> *(empty)*", ""]
    lines += [
        "## Evidence",
        "",
        "| Session | Bundle | Transcript | Telemetry turns |",
        "|---|---|---|---|",
    ]
    for bundle in bundles:
        shown = display_path(bundle.path)
        lines.append(
            f"| `{bundle.path.name}` | `{shown}/` "
            f"| `{shown}/transcript.md` | {len(bundle.turns)} |"
        )
    lines += [
        "",
        "Raw evidence (not summarised): `session.meta.json`, `telemetry.jsonl`, `survey.md`,",
        "`obs_sheet.md`, `session_log.md`, `raw/` and `manifest.json` in each bundle.",
        "",
    ]
    return "\n".join(lines), passed


# --------------------------------------------------------------------------- helper modes


def merge_telemetry(bundle: Path) -> int:
    """Append any record from raw/*.jsonl that telemetry.jsonl does not already hold."""
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


# --------------------------------------------------------------------------- main


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Score the P2 human playtest round.")
    parser.add_argument("--dir", default=str(DEFAULT_DIR), help="round directory (default: %(default)s)")
    parser.add_argument("--out", default=None, help="RESULT.md path (default: <dir>/RESULT.md)")
    parser.add_argument(
        "--expect", type=int, default=EXPECTED_SESSIONS, help="required session count (default: 3)"
    )
    parser.add_argument(
        "--allow-synthetic",
        action="store_true",
        help="allow fixture bundles (session.meta.json synthetic=true); output is labelled",
    )
    parser.add_argument("--validate", metavar="BUNDLE", help="validate one bundle and exit")
    parser.add_argument("--merge", metavar="BUNDLE", help="merge raw/*.jsonl into telemetry.jsonl")
    parser.add_argument("--render", metavar="BUNDLE", help="rewrite BUNDLE/transcript.md")
    parser.add_argument("--manifest", metavar="BUNDLE", help="write BUNDLE/manifest.json")
    args = parser.parse_args(argv)

    if args.merge:
        bundle = Path(args.merge).expanduser().resolve()
        if not (bundle / "session.meta.json").is_file():
            print(f"merge: {bundle} has no session.meta.json — is this a session bundle?", file=sys.stderr)
            return 2
        added = merge_telemetry(bundle)
        records, _ = load_telemetry(bundle / "telemetry.jsonl")
        print(f"merge: {bundle.name}: +{added} record(s), {len(records)} total, {len(telemetry_turns(records))} turn(s)")
        return 0

    if args.render:
        bundle_path = Path(args.render).expanduser().resolve()
        for name in ("session.meta.json", "telemetry.jsonl"):
            if not (bundle_path / name).is_file():
                print(f"render: {bundle_path} has no {name}", file=sys.stderr)
                return 2
        (bundle_path / "transcript.md").write_text(render_transcript(bundle_path), encoding="utf-8")
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
    codes = [bundle.participant for bundle in bundles]
    if len(set(codes)) != len(codes):
        print(
            "ERROR: duplicate participant codes: "
            + ", ".join(sorted(codes))
            + ". Round 1 needs three different people; give each a distinct code (P1, P2, P3).",
            file=sys.stderr,
        )
        return 2
    for bundle in bundles:
        if bundle.played_s < 420:
            print(
                f"warn: {bundle.path.name}: the observer logged {bundle.played_s:.0f}s of play; "
                "the M1 exit criterion asks for about 10 minutes. Check the session log before "
                "citing this round.",
                file=sys.stderr,
            )
        if bundle.duration_s is not None and abs(bundle.duration_s - bundle.played_s) > 180:
            print(
                f"warn: {bundle.path.name}: session.meta.json duration "
                f"{bundle.duration_s:.0f}s disagrees with the observer's played time "
                f"{bundle.played_s:.0f}s by more than 3 minutes",
                file=sys.stderr,
            )
    synthetic = any(bundle.synthetic for bundle in bundles)
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
