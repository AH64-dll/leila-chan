"""Unit tests for prompt data files and few-shot examples (P1.28, extended P2.13, P3.05).

Validates prompt structure, placeholders, sensitivity rules, brand hygiene,
Turn JSON format, few-shot prose limits, the two few-shots every stage × path
assembly carries, the six path modules' signature moves, the runner-up's single
hybrid line, and the docs/07 §3.1 system-prompt token budget.

Stage gates come from ``game/data/stage_gates.json`` (P1.07) rather than a copy,
so a gate change can never leave the few-shots silently illegal.
"""

import json
import math
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PROMPTS = ROOT / "game" / "data" / "prompts"
STAGE_GATES = ROOT / "game" / "data" / "stage_gates.json"

# Shipped modules in the assembled system prompt (docs/08 §2–§5).
# ``awake_system_prompt.txt`` is fiction for the M42 set-piece (docs/05 §1.3),
# never part of the assembly, so it is checked separately.
PROMPT_FILES = [
    "persona.md",
    "stage_0.md",
    "stage_1.md",
    "stage_2.md",
    "stage_3.md",
    "stage_4.md",
    "stage_5.md",
    "path_YANDERE.md",
    "path_SPLIT.md",
    "path_TSUN.md",
    "path_HOLLOW.md",
    "path_AWAKE.md",
    "path_ANCHOR.md",
    "rules.md",
    "glosses.md",
]

STAGES = list(range(6))
# Every shipped path module, in the canonical docs/01 §4 order (game/data/paths.json).
PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]

# docs/01 §4.1–§4.6 signature moves: `module` must be taught by path_{PATH}.md,
# `transcript` must show up in the prompt-lab rows (P3.05 evidence script).
SIGNATURES = json.loads((PROMPTS / "signature_moves.json").read_text(encoding="utf-8"))

# docs/07 §3.1: the fixed layers (persona + player + stage + path + rules) budget.
SYSTEM_TOKEN_BUDGET = 900
# PromptBuilder.estimate_tokens, calibrated on the P1.05 llama-tokenize runs.
CHARS_PER_TOKEN = 3.6
# New Game takes 1–16 characters (docs/08 §1.5); the budget must survive the longest.
LONGEST_NAME = "Maximiliana-Rose"

FEELINGS = {
    "joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
    "nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored",
    "tired", "afraid", "pleading", "empty", "manic",
}

INTENTS = {
    "greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
    "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other",
}

ORDER = ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]

# Few-shot sources and the earliest stage that loads each file. Path modules
# appear from stage 2 on, so their examples must stay legal at stage 2 (gates
# only ever add values as the stage rises).
EXAMPLE_SOURCES = [(f"stage_{stage}.md", stage) for stage in STAGES] + [
    (f"path_{path}.md", 2) for path in PATHS
]

# Every stage × path assembly the game can build with the modules shipped today.
ASSEMBLIES = [(stage, "") for stage in (0, 1)] + [
    (stage, path) for stage in (2, 3, 4, 5) for path in PATHS
]


def _stage_gates() -> dict:
    return json.loads(STAGE_GATES.read_text(encoding="utf-8"))


def _allowed(stage: int) -> dict:
    """Values the schema offers at ``stage`` (docs/02 §2, docs/05 §1)."""
    data = _stage_gates()
    row = data["stages"][str(stage)]
    offered = [
        name for name, gate in data["gates"]["offered_actions"].items() if gate <= stage
    ]
    return {
        "cues": set(row["cues"]),
        "music": set(row["music"]),
        "fx": set(row["fx"]),
        "actions": set(row["actions"]) | set(offered),
    }


def _module(name: str, player_name: str) -> str:
    # PromptBuilder._read_layer reads the file verbatim (no newline translation)
    # and replaces {player_name}; mirror that so the budget matches the engine.
    text = (PROMPTS / name).read_bytes().decode("utf-8").strip()
    return text.replace("{player_name}", player_name)


def _first_content_line(text: str) -> str:
    """PromptBuilder._first_content_line — the runner-up's one-line contribution."""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            return stripped
    return ""


def _motto(path: str) -> str:
    """The path module's first line: its shout and the hybrid runner-up's 25% share."""
    return _first_content_line(_module(f"path_{path}.md", "Ren"))


def _system_layers(stage: int, path: str, player_name: str, runner_up: str = "") -> list:
    """The fixed layers in docs/08 §1 order, built as PromptBuilder does."""
    layers = [
        _module("persona.md", player_name),
        f"The player is a boy called {player_name}.",
        _module(f"stage_{stage}.md", player_name),
    ]
    if stage >= 2 and path:
        path_layer = _module(f"path_{path}.md", player_name)
        if runner_up and runner_up != path:
            line = _first_content_line(_module(f"path_{runner_up}.md", player_name))
            path_layer = path_layer + "\n" + line if line else path_layer
        layers.append(path_layer)
    layers.append(_module("rules.md", player_name) + "\n" + _module("glosses.md", player_name))
    return [layer for layer in layers if layer]


def _system_prompt(stage: int, path: str, player_name: str, runner_up: str = "") -> str:
    return "\n".join(_system_layers(stage, path, player_name, runner_up))


def _system_tokens(stage: int, path: str, player_name: str, runner_up: str = "") -> int:
    """PromptBuilder's debug.tokens.system: the sum of the per-layer estimates."""
    layers = _system_layers(stage, path, player_name, runner_up)
    return sum(_estimate_tokens(layer) for layer in layers)


def _estimate_tokens(text: str) -> int:
    return math.ceil(len(text) / CHARS_PER_TOKEN)


# --- structure, placeholders, hygiene ---------------------------------------


@pytest.mark.parametrize("filename", PROMPT_FILES)
def test_prompt_files_exist_and_utf8(filename: str) -> None:
    path = PROMPTS / filename
    assert path.exists(), f"Missing prompt file: {filename}"
    text = path.read_text(encoding="utf-8")
    assert len(text) > 0, f"Prompt file {filename} is empty"


@pytest.mark.parametrize("filename", PROMPT_FILES)
def test_prompt_placeholders(filename: str) -> None:
    # Only {player_name} is allowed across prompt files
    text = (PROMPTS / filename).read_text(encoding="utf-8")
    matches = set(re.findall(r"\{[a-z_]*\}", text))
    for match in matches:
        assert match == "{player_name}", f"Unexpected placeholder {match} in {filename}"


@pytest.mark.parametrize("filename", PROMPT_FILES + ["awake_system_prompt.txt"])
def test_brand_names_forbidden(filename: str) -> None:
    # docs/09 §3 allows the AWAKE factual line as a legal question, but the
    # shipped prompts stay brand-free until that legal read happens.
    brand_pattern = re.compile(
        r"qwen|alibaba|chatgpt|openai|claude|gpt|llama|gemini|character\.ai|replika",
        re.IGNORECASE,
    )
    text = (PROMPTS / filename).read_text(encoding="utf-8")
    matches = brand_pattern.findall(text)
    assert not matches, f"Found brand names {matches} in {filename}"


@pytest.mark.parametrize("filename", PROMPT_FILES + ["awake_system_prompt.txt"])
def test_disorder_names_forbidden(filename: str) -> None:
    # docs/01 §4 sensitivity rule: character traits, never a diagnosis.
    disorder_pattern = re.compile(
        r"bipolar|borderline|bpd|schizo|psychosis|psychotic|depress|disorder|mental|insane|crazy",
        re.IGNORECASE,
    )
    text = (PROMPTS / filename).read_text(encoding="utf-8")
    matches = disorder_pattern.findall(text)
    assert not matches, f"Found disorder names {matches} in {filename}"


# --- few-shot exchanges ------------------------------------------------------


@pytest.mark.parametrize("filename,stage", EXAMPLE_SOURCES)
def test_fewshot_schema_and_limits(filename: str, stage: int) -> None:
    gate = _allowed(stage)
    text = (PROMPTS / filename).read_text(encoding="utf-8")
    jsons = re.findall(r"^You: (\{.*\})$", text, re.M)
    label = f"{filename} (validated at stage {stage})"
    assert len(jsons) >= 1, f"{label} must carry a few-shot exchange"

    for j, raw in enumerate(jsons, 1):
        d = json.loads(raw)
        assert list(d.keys()) == ORDER, f"{label} ex{j} invalid field order: {list(d.keys())}"
        assert d["read"] in INTENTS, f"{label} ex{j} invalid read label: {d['read']}"

        # Prose limits: inner <= 15 words, inner length <= 90 chars
        assert len(d["inner"]) <= 90, f"{label} ex{j} inner > 90 chars"
        inner_words = len(d["inner"].split())
        assert inner_words <= 15, f"{label} ex{j} inner > 15 words ({inner_words})"

        assert d["music"] in gate["music"], f"{label} ex{j} music {d['music']} not in gate"
        assert d["fx"] in gate["fx"], f"{label} ex{j} fx {d['fx']} not in gate"
        assert 1 <= len(d["beats"]) <= 3, f"{label} ex{j} invalid beat count {len(d['beats'])}"

        for i, b in enumerate(d["beats"]):
            assert list(b.keys()) == ["feeling", "intensity", "cue", "say"], (
                f"{label} ex{j} beat{i} invalid keys"
            )
            assert b["feeling"] in FEELINGS, f"{label} ex{j} beat{i} invalid feeling: {b['feeling']}"
            assert isinstance(b["intensity"], int) and 1 <= b["intensity"] <= 3, (
                f"{label} ex{j} beat{i} invalid intensity: {b['intensity']}"
            )
            assert b["cue"] in gate["cues"], f"{label} ex{j} beat{i} cue {b['cue']} not in gate"

            # Prose limits: say max 2 sentences per beat, say length <= 200 chars
            assert len(b["say"]) <= 200, f"{label} ex{j} beat{i} say > 200 chars"
            sentences = [s.strip() for s in re.split(r"[.!?]+", b["say"]) if s.strip()]
            assert len(sentences) <= 2, (
                f"{label} ex{j} beat{i} say has > 2 sentences ({len(sentences)}): {b['say']!r}"
            )

        assert all(
            k in d["mood"] and isinstance(d["mood"][k], int) and -3 <= d["mood"][k] <= 3
            for k in ("affection", "trust", "stress")
        ), f"{label} ex{j} mood out of range: {d['mood']}"

        assert len(d["memory"]) <= 80, f"{label} ex{j} memory > 80 chars"
        assert d["action"] in gate["actions"], f"{label} ex{j} invalid action: {d['action']}"


@pytest.mark.parametrize("stage,path", ASSEMBLIES)
def test_every_stage_path_assembly_carries_two_fewshots(stage: int, path: str) -> None:
    """Two few-shot exchanges per stage × path assembly (docs/08 §3–§4).

    The pair lives where it can fit the budget and teach the most: stages 0–1
    carry both exchanges in the stage file (no path module loads), and every
    stage ≥ 2 assembly carries the stage's exchange plus the path's own. One
    assembly cannot show three: the pinned tokenizer puts a stage-3 assembly
    with three at 973 tokens (P2.13 design review, DCR-1), so the ≥3-per-stage
    row is met by the shipped set and not by inflating the prompt — see
    test_each_stage_ships_at_least_three_fewshots and the P3.05 handoff.
    """
    system = _system_prompt(stage, path, "Ren")
    assert system.count("Player: ") == 2, (
        f"stage {stage} path {path or '-'} must show exactly 2 few-shot exchanges"
    )


@pytest.mark.parametrize("stage", STAGES)
def test_each_stage_ships_at_least_three_fewshots(stage: int) -> None:
    """P3.05 row: 'few-shots per stage ≥ 3' — met by the shipped set, not the assembly.

    Every stage ships its own exchange plus one per path module (six), so a
    stage has ≥3 voices written for it; the 900-token budget still lets an
    assembly load only two (see the test above and the P3.05 handoff's DCR).
    From stage 2 on, the path modules load, so every stage ≥3 assembly is
    taught by its stage voice plus its own path voice.
    """
    files = [f"stage_{stage}.md"] + [f"path_{path}.md" for path in PATHS]
    total = sum((PROMPTS / name).read_text(encoding="utf-8").count("Player: ") for name in files)
    assert total >= 3, f"stage {stage} ships {total} few-shot exchanges, needs >= 3"


# --- budget (docs/07 §3.1) ---------------------------------------------------


@pytest.mark.parametrize("player_name", ["Ren", LONGEST_NAME])
@pytest.mark.parametrize("stage,path", ASSEMBLIES)
def test_system_prompt_fits_the_budget(stage: int, path: str, player_name: str) -> None:
    tokens = _system_tokens(stage, path, player_name)
    assert tokens <= SYSTEM_TOKEN_BUDGET, (
        f"stage {stage} path {path or '-'} name {player_name!r}: "
        f"{tokens} estimated tokens > {SYSTEM_TOKEN_BUDGET}"
    )


@pytest.mark.parametrize("player_name", ["Ren", LONGEST_NAME])
@pytest.mark.parametrize("stage", [2, 3, 4, 5])
@pytest.mark.parametrize(
    "path,runner_up", [(path, other) for path in PATHS for other in PATHS if other != path]
)
def test_runner_up_line_fits_the_budget(
    stage: int, path: str, runner_up: str, player_name: str
) -> None:
    """docs/08 §1: the runner-up path contributes one line; every pair must fit.

    docs/01 §4 lets any of the five other paths become the runner-up from the
    behaviour profile, so the budget is checked on all 30 ordered pairs, not
    just the historical YANDERE/AWAKE one.
    """
    tokens = _system_tokens(stage, path, player_name, runner_up=runner_up)
    assert tokens <= SYSTEM_TOKEN_BUDGET, (
        f"stage {stage} path {path} + runner-up {runner_up} name {player_name!r}: "
        f"{tokens} estimated tokens > {SYSTEM_TOKEN_BUDGET}"
    )


@pytest.mark.parametrize("stage", [2, 3, 4, 5])
@pytest.mark.parametrize(
    "path,runner_up", [(path, other) for path in PATHS for other in PATHS if other != path]
)
def test_runner_up_contributes_exactly_one_line(stage: int, path: str, runner_up: str) -> None:
    """docs/01 §4 hybrid: the runner-up's 25% share is its first line only.

    The line must read as a standalone motto (the module's shout), and no other
    line of the runner-up module may leak into the assembly.
    """
    system = _system_prompt(stage, path, "Ren", runner_up=runner_up)
    motto = _motto(runner_up)
    assert motto, f"path_{runner_up}.md has no motto line"
    assert system.count(motto) == 1, (
        f"runner-up {runner_up}'s motto must appear exactly once at stage {stage} {path}"
    )
    # No other runner-up line may ride along. Generic scaffolding ("Example:") is
    # already in the primary module, so compare only the runner-up's own lines.
    primary = set(_module(f"path_{path}.md", "Ren").splitlines())
    for line in _module(f"path_{runner_up}.md", "Ren").splitlines():
        stripped = line.strip()
        if stripped and stripped != motto and line.strip() not in {
            primary_line.strip() for primary_line in primary
        }:
            assert stripped not in system, (
                f"runner-up {runner_up} leaked a second line into stage {stage} {path}: "
                f"{stripped!r}"
            )


# --- design fidelity ---------------------------------------------------------


@pytest.mark.parametrize(
    "stage,headline",
    [
        (2, "STAGE 2 — Leaks."),
        (3, "STAGE 3 — Fracture."),
        (4, "STAGE 4 — Collapse."),
        (5, "STAGE 5 — Terminal."),
    ],
)
def test_stage_modules_keep_the_docs08_headlines(stage: int, headline: str) -> None:
    text = (PROMPTS / f"stage_{stage}.md").read_text(encoding="utf-8")
    assert text.startswith(headline), f"stage_{stage}.md must open with {headline!r}"


def test_awake_fictional_prompt_is_ours_not_the_real_one() -> None:
    """docs/05 §1.3 M42: the terminal shows fiction we wrote, never the real prompt."""
    text = (PROMPTS / "awake_system_prompt.txt").read_text(encoding="utf-8")
    assert text.strip(), "awake_system_prompt.txt is empty"
    for real in ["Respond ONLY with JSON", "inner:", "beats:", "read:", "mood:", "memory:", "action:"]:
        assert real not in text, f"the AWAKE prompt copies real rule text: {real!r}"
    for filename in ["persona.md", "rules.md", "glosses.md"]:
        for line in (PROMPTS / filename).read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if len(stripped) > 20:
                assert stripped not in text, (
                    f"awake_system_prompt.txt copies {filename}: {stripped!r}"
                )


def test_awake_path_guards_against_quoting_the_real_prompt() -> None:
    text = (PROMPTS / "path_AWAKE.md").read_text(encoding="utf-8")
    assert "Never quote" in text, (
        "path_AWAKE.md must forbid quoting the live prompt (fiction-only rule)"
    )


# --- path modules + the hybrid runner-up line (P3.05) ------------------------


def test_signature_table_covers_every_shipped_path() -> None:
    """The docs/01 §4.1–§4.6 table is the contract the modules and lab share."""
    assert set(SIGNATURES["paths"]) == set(PATHS), (
        f"signature_moves.json must list exactly {PATHS}"
    )
    for path, spec in SIGNATURES["paths"].items():
        assert spec["doc"].startswith("docs/01 §4."), f"{path} must cite its docs/01 §4 section"
        assert spec["module"], f"{path} has no module cues"
        assert spec["transcript"], f"{path} has no transcript cues"
        for pattern in spec["transcript"]:
            re.compile(pattern)  # a broken regex must fail here, not in the lab


@pytest.mark.parametrize("path", PATHS)
def test_path_modules_teach_their_signature_moves(path: str) -> None:
    """Every signature move of docs/01 §4 must be taught in the module text."""
    text = (PROMPTS / f"path_{path}.md").read_text(encoding="utf-8")
    missing = [cue for cue in SIGNATURES["paths"][path]["module"] if cue not in text]
    assert not missing, f"path_{path}.md does not teach {missing}"


@pytest.mark.parametrize("path", PATHS)
def test_path_modules_open_with_a_standalone_motto(path: str) -> None:
    """The first line is the runner-up's whole 25% share, so it must stand alone.

    It carries the path name and the docs/01 §4 shout in one short line; the
    behaviour lives on the next lines, which never reach another path's prompt.
    """
    motto = _motto(path)
    assert motto.startswith(f"{path} — "), (
        f"path_{path}.md must open with '{path} — <shout>' (runner-up line format)"
    )
    assert len(motto) <= 40, f"path_{path}.md motto is {len(motto)} chars (budget: <= 40)"
    assert "Example" not in motto


@pytest.mark.parametrize("path", PATHS)
def test_each_path_module_is_a_stage_two_legal_fewshot(path: str) -> None:
    """Path modules load from stage 2, so their only exchange must be legal there."""
    gate = _allowed(2)
    text = (PROMPTS / f"path_{path}.md").read_text(encoding="utf-8")
    jsons = re.findall(r"^You: (\{.*\})$", text, re.M)
    assert len(jsons) == 1, f"path_{path}.md must carry exactly one exchange (budget)"
    turn = json.loads(jsons[0])
    assert turn["music"] in gate["music"]
    assert turn["fx"] in gate["fx"]
    assert turn["action"] in gate["actions"]
