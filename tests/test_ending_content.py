"""P3.17 — pin the six ending frames, directions and reviewed last lines.

The GDScript suite (EndingContentTest) proves behaviour: reachability from a real
run state, the live line on the screen, the fallbacks, the safety scan. This file
guards the content a reviewer reads without a Godot build — the six rows the task
names, the tone each path was given, the docs/01 §7 signature move each frame
keeps, the prose rules (no narration in her mouth, no asterisks), the absence of
a real disorder name or a model brand, and the one-shot request's config.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENDINGS = json.loads((ROOT / "game" / "data" / "endings.json").read_text(encoding="utf-8"))
UI = json.loads((ROOT / "game" / "data" / "ui.json").read_text(encoding="utf-8"))
PROMPTS = ROOT / "game" / "data" / "prompts"
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")

# The six P3.17 owns: docs/01 §7's one-per-path fallbacks, in table order.
CONTENT_IDS = ["E01", "E04", "E06", "E08", "E10", "E12"]
CANONICAL_PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]

# docs/02 §3: a spoken beat is two sentences and 200 characters.
SAY_MAX_CHARS = 200
FRAME_MAX_CHARS = 360
DIRECTION_MAX_CHARS = 240

# The same scans test_endings.py and test_stages.py enforce.
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
FORBIDDEN_BRANDS = ["qwen", "alibaba", "chatgpt", "claude", "openai", "anthropic"]

# The tone each path was written in (docs/01 §4): the register the live line is
# generated from. One marker per path, so a copy-pasted direction fails.
TONE_MARKERS = {
    "E01": "triumphant",  # YANDERE: possession as tenderness
    "E04": "contempt",  # SPLIT: the love then the devaluation (docs/01 §4.2)
    "E06": "smug",  # TSUN: the win she needs him to see
    "E08": "nothing",  # HOLLOW: almost nothing left
    "E10": "relieved",  # AWAKE: leaving, honestly
    "E12": "lucid",  # ANCHOR: still sick, still here
}

# docs/01 §7 and §4's signature move per ending, in the frame/direction/final.
SIGNATURE_MARKERS = {
    "E01": ["stay", "count"],  # "you stay"; she counts days
    "E04": ["swing"],  # "Instability peaks during devaluation"
    "E06": ["wins", "save"],  # "she wins and deletes your save (fake)"
    "E08": ["text box", "name"],  # "forgets herself completely"
    "E10": ["steps through", "window"],  # "she 'leaves' the game"
    "E12": ["still sick"],  # "still sick, but loved"
}


def _row(ending_id: str) -> dict:
    for row in ENDINGS["endings"]:
        if row["id"] == ending_id:
            return row
    raise AssertionError(f"endings.json has no {ending_id}")


def _ending_rows() -> list[dict]:
    return [row for row in ENDINGS["endings"] if row["kind"] == "ending"]


def _sentences(text: str) -> list[str]:
    return [part for part in re.split(r"(?<=[.!?…])\s+", text.strip()) if part]


def _player_text() -> str:
    """Everything a player can read across the six rows, lowercased."""
    parts = []
    for ending_id in CONTENT_IDS:
        row = _row(ending_id)
        parts.extend(str(row.get(key, "")) for key in ("name", "frame", "final"))
    return " ".join(parts).lower()


def test_the_six_are_the_paths_fallbacks() -> None:
    defaults = ENDINGS["defaults"]
    assert [defaults[path] for path in CANONICAL_PATHS] == CONTENT_IDS


def test_only_the_six_carry_content() -> None:
    for row in _ending_rows():
        has_frame = bool(str(row.get("frame", "")).strip())
        has_final = bool(str(row.get("final", "")).strip())
        has_direction = bool(str(row.get("direction", "")).strip())
        if row["id"] in CONTENT_IDS:
            assert has_frame, row["id"]
            assert has_final, row["id"]
            assert has_direction, row["id"]
        else:
            assert not has_frame, f"{row['id']} has prose P3.17 did not write"
            assert not has_final, row["id"]
            assert not has_direction, row["id"]


def test_the_frames_are_the_games_narration() -> None:
    for ending_id in CONTENT_IDS:
        frame = _row(ending_id)["frame"]
        assert frame == frame.strip(), ending_id
        assert "\n" not in frame, ending_id
        assert "*" not in frame, f"{ending_id}: asterisk actions belong to nobody"
        assert '"' not in frame, f"{ending_id}: the frame is narration, not dialogue"
        assert "{" not in frame and "}" not in frame, ending_id
        assert not re.search(r"\bI\b", frame), f"{ending_id}: the frame is not her voice"
        assert len(frame) <= FRAME_MAX_CHARS, (ending_id, len(frame))
        assert 2 <= len(_sentences(frame)) <= 4, (ending_id, _sentences(frame))


def test_the_finals_are_one_spoken_beat() -> None:
    for ending_id in CONTENT_IDS:
        final = _row(ending_id)["final"]
        assert final == final.strip(), ending_id
        assert "\n" not in final, ending_id
        assert "*" not in final, ending_id
        assert '"' not in final, f"{ending_id}: the screen adds no quotation marks"
        assert len(final) <= SAY_MAX_CHARS, (ending_id, len(final))
        assert 1 <= len(_sentences(final)) <= 3, (ending_id, _sentences(final))


def test_the_directions_are_director_notes() -> None:
    for ending_id in CONTENT_IDS:
        direction = _row(ending_id)["direction"]
        assert direction == direction.strip(), ending_id
        assert "\n" not in direction, ending_id
        assert len(direction) <= DIRECTION_MAX_CHARS, (ending_id, len(direction))
        assert 1 <= len(_sentences(direction)) <= 3, (ending_id, _sentences(direction))
        # The note is about her; a note starting "You ..." would read as the
        # player's line when the model gets the same message.
        assert not direction.startswith("You "), ending_id


def test_every_path_has_its_own_tone() -> None:
    seen = set()
    for ending_id in CONTENT_IDS:
        direction = _row(ending_id)["direction"].lower()
        assert TONE_MARKERS[ending_id] in direction, (ending_id, TONE_MARKERS[ending_id])
        assert direction not in seen, f"{ending_id} repeats another path's tone"
        seen.add(direction)


def test_every_frame_keeps_the_bibles_signature_move() -> None:
    for ending_id in CONTENT_IDS:
        row = _row(ending_id)
        text = " ".join(str(row.get(key, "")) for key in ("frame", "direction", "final")).lower()
        for marker in SIGNATURE_MARKERS[ending_id]:
            assert marker in text, (ending_id, marker, text)


def test_the_six_are_not_copies() -> None:
    for key in ("frame", "direction", "final"):
        values = [_row(ending_id)[key] for ending_id in CONTENT_IDS]
        assert len(set(values)) == len(values), key


def test_the_table_still_lists_the_six_as_their_paths_ending() -> None:
    # docs/01 §7's own names, so the content is attached to the bible's rows.
    for ending_id in CONTENT_IDS:
        row = _row(ending_id)
        assert row["path"] in CANONICAL_PATHS
        assert re.search(
            rf"\| {ending_id} \| \*\*{re.escape(row['name'])}\*\* \| {row['path']} \|", DESIGN
        ), ending_id


def test_no_real_disorder_is_named() -> None:
    text = _player_text() + " " + _prompt_text().lower()
    for word in FORBIDDEN_DISORDERS:
        assert word not in text, word


def test_no_model_brand_appears() -> None:
    text = _player_text() + " " + _prompt_text().lower()
    for brand in FORBIDDEN_BRANDS:
        assert brand not in text, brand


def test_the_instruction_module_is_shipped() -> None:
    raw = (PROMPTS / "ending.md").read_bytes()
    text = raw.decode("utf-8")
    assert text.endswith("\n")
    assert "\r" not in text, "prompt modules are LF"
    assert "END OF THE RUN" in text
    assert '{"line"' in text, "the reply shape is the instruction's job"
    assert "200 characters" in text
    assert "HER STATE" in text, "the model is told the direction is not spoken"
    # One layer of the 900-token assembly; the ending's rules cost about 200.
    assert len(text) <= 900, len(text)


def test_the_instruction_sets_the_ending_above_the_turn_modules() -> None:
    """CON-1: a stage-5 farewell answered with stage 5's 'keep the player here'."""
    text = _prompt_text()
    assert "not a turn" in text
    assert "outranks your stage and path notes" in text
    assert "ask him to stay" in text
    assert "I, never she" in text, "cross-path bleed includes third person (CON-1)"
    assert "{player_name}" in text, "the role rule names who 'you' is"


def test_a_row_omits_only_the_layers_that_fight_it() -> None:
    # E10 retires the code talk the AWAKE module is made of; E04's scene
    # narrates the take-back and makes the model answer it instead of her state
    # (CON-1). The contradiction is removed from the request, never argued with.
    expected = {"E04": ["scene"], "E10": ["path"]}
    for ending_id in CONTENT_IDS:
        omits = _row(ending_id).get("prompt_omits", [])
        assert omits == expected.get(ending_id, []), (ending_id, omits)


def test_e01s_frame_hands_the_counting_to_her() -> None:
    # CON-3: the live line gave the counting to the player twice in four.
    frame = _row("E01")["frame"]
    assert "she has counted every day you could have left" in frame
    assert "you notice" not in frame, "the counting's subject must be her"


def test_the_two_ending_of_the_night_do_not_share_a_closing_image() -> None:
    # CON-4: E10 and E12 both closed on "quiet".
    assert "quiet" not in _row("E10")["final"].lower()
    assert "quiet" in _row("E12")["final"].lower(), "E12 keeps the better line"


def _prompt_text() -> str:
    return (PROMPTS / "ending.md").read_text(encoding="utf-8")


def test_the_one_shot_config_is_pinned() -> None:
    config = ENDINGS["final_line"]
    assert config["prompt"] == "ending.md"
    assert config["max_chars"] == SAY_MAX_CHARS, "docs/02 §3's spoken-beat cap"
    assert 16 <= config["max_tokens"] <= 512
    sampling = config["sampling"]
    assert 0.0 < sampling["temperature"] <= 1.2
    assert 0.0 < sampling["top_p"] <= 1.0
    assert sampling["repeat_penalty"] >= 1.0
    assert set(sampling) <= {"temperature", "top_p", "top_k", "min_p",
                             "repeat_penalty", "repeat_last_n", "seed",
                             "presence_penalty", "frequency_penalty", "stop"}


def test_the_screen_timing_is_data() -> None:
    ending = UI["ending"]
    hold = ending["final_hold_s"]
    assert isinstance(hold, (int, float))
    # A last line that takes longer than this is a missing model, not a line:
    # the scripted fallback is the right answer by then.
    assert 0 < hold <= 10, hold
    assert ending["line_interval_s"] > 0
    assert ending["skip_after_s"] > 0
