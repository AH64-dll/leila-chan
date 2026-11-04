"""P2.12 — pin the docs/01 §4 fracture paths and the keyword profile data.

The GDScript suites (game/tests/PathsTest.gd, ProfileKeywordsTest.gd) prove the
behaviour of GameState/Paths/ProfileKeywords; this file guards the tables a
reviewer reads without a Godot build: every score formula must be the bible's
term for term (parsed out of docs/01 itself), the six ids must be the casting
keys, the Stage-2/Stage-3 pair must be the doc's, and the keyword rules must
only write counters the profile actually stores.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATHS = json.loads((ROOT / "game" / "data" / "paths.json").read_text(encoding="utf-8"))
KEYWORDS = json.loads(
    (ROOT / "game" / "data" / "profile_keywords.json").read_text(encoding="utf-8")
)
PROFILE_MAP = json.loads(
    (ROOT / "game" / "data" / "profile_map.json").read_text(encoding="utf-8")
)
CASTING = json.loads((ROOT / "data" / "casting.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
PROMPTS_DOC = (ROOT / "docs" / "08_PROMPTS_AND_CONTENT.md").read_text(encoding="utf-8")

# docs/01 §2's behaviour-profile tag list, verbatim.
DOC_COUNTERS = [
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
]

# The §4 formulas name three counters §2's tag list does not enumerate.
FORMULA_ONLY_COUNTERS = {"broken_promises", "flattery_rejected", "ignored_questions"}

# docs/01 §4.1–§4.6 order; TSUN-BREAK is the doc name, TSUN the casting/UI id.
DOC_PATH_ORDER = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]

# docs/01 §4 sensitivity rule; same list tests/test_scenarios.py enforces.
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


def _doc_formulas() -> dict[str, list[tuple[str, str, int, int]]]:
    """docs/01 §4's score block, parsed into (kind, name, weight, divisor) terms."""
    rows = re.findall(r"^score\[(\w+)\]\s*=\s*(.+)$", DESIGN, re.MULTILINE)
    assert len(rows) == 6, f"docs/01 §4 should list six scores, found {len(rows)}"
    formulas: dict[str, list[tuple[str, str, int, int]]] = {}
    for path_id, rhs in rows:
        normalised = rhs.replace("−", "-").replace("·", "*")
        normalised = normalised.replace("(", " ").replace(")", " ").replace(" ", "")
        terms: list[tuple[str, str, int, int]] = []
        for chunk in re.split(r"(?=[+-])", normalised.strip()):
            if not chunk:
                continue
            sign = -1 if chunk.startswith("-") else 1
            body = chunk.lstrip("+-")
            metre = re.fullmatch(r"([A-Za-z_]+)/(\d+)", body)
            if metre:
                terms.append(("meter", metre.group(1).lower(), sign, int(metre.group(2))))
                continue
            name_first = re.fullmatch(r"([A-Za-z_]+)\*(\d+)", body)
            if name_first:
                terms.append(("counter", name_first.group(1), sign * int(name_first.group(2)), 1))
                continue
            weight_first = re.fullmatch(r"(\d+)\*([A-Za-z_]+)", body)
            if weight_first:
                terms.append(
                    ("counter", weight_first.group(2), sign * int(weight_first.group(1)), 1)
                )
                continue
            terms.append(("counter", body, sign, 1))
        formulas[path_id] = terms
    return formulas


def _data_terms() -> dict[str, list[tuple[str, str, int, int]]]:
    out: dict[str, list[tuple[str, str, int, int]]] = {}
    for path_id, terms in PATHS["scores"].items():
        rows: list[tuple[str, str, int, int]] = []
        for term in terms:
            if "counter" in term:
                rows.append(("counter", term["counter"], int(term["weight"]), 1))
            else:
                rows.append(
                    ("meter", term["meter"], int(term["weight"]), int(term.get("divisor", 1)))
                )
        out[path_id] = rows
    return out


def test_paths_table_shape() -> None:
    assert set(PATHS) == {
        "version",
        "doc",
        "assign_stage",
        "lock_stage",
        "paths",
        "scores",
    }
    assert PATHS["version"] == 1
    assert PATHS["doc"].strip(), "paths.json carries no doc string"
    assert PATHS["paths"] == DOC_PATH_ORDER
    assert set(PATHS["scores"]) == set(DOC_PATH_ORDER)


def test_score_formulas_are_the_bible_formulas() -> None:
    assert _data_terms() == _doc_formulas()


def test_stage_rule_is_the_doc_rule() -> None:
    # docs/01 §4: "soft-assigned at Stage 2 ... until Stage 3, where it locks".
    assert PATHS["assign_stage"] == 2
    assert PATHS["lock_stage"] == 3
    assert "soft-assigned at Stage 2" in DESIGN
    assert "where it locks" in DESIGN


def test_yandere_fixation_term_is_a_divisor_not_a_float_factor() -> None:
    # Fixation/10 must stay an exact division: storing 0.1 as a weight would make
    # the YANDERE score inexact and hide real ties from the recency tie-break.
    fixation = [term for term in PATHS["scores"]["YANDERE"] if term.get("meter") == "fixation"]
    assert fixation == [{"meter": "fixation", "weight": 1, "divisor": 10}]


def test_path_ids_are_the_casting_keys() -> None:
    assert set(CASTING["paths"]) == set(DOC_PATH_ORDER)
    assert len(CASTING["paths"]) == 6


def test_formula_counters_cover_the_profile() -> None:
    score_counters = {
        term["counter"]
        for terms in PATHS["scores"].values()
        for term in terms
        if "counter" in term
    }
    # Every counter the formulas read is either a §2 tag or one of §4's three.
    assert score_counters - set(DOC_COUNTERS) == FORMULA_ONLY_COUNTERS
    # The read map only writes §2 tags; the keyword rules write the rest.
    read_counters = {
        counter
        for bumps in PROFILE_MAP["read_to_profile"].values()
        for counter in bumps
    }
    assert read_counters <= set(DOC_COUNTERS)


def test_hybrid_runner_up_matches_the_prompt_layout() -> None:
    # docs/01 §4's 25% hybrid is rendered by docs/08 §1 as one runner-up line.
    assert "runner-up path contributes 25% of its prompt module" in DESIGN
    assert "path_{primary}.md (+ 1 line from runner-up)" in PROMPTS_DOC


def test_keywords_table_shape() -> None:
    assert set(KEYWORDS) == {"version", "doc", "control", "apathy", "flattery_rejected"}
    assert KEYWORDS["version"] == 1
    assert KEYWORDS["doc"].strip(), "profile_keywords.json carries no doc string"
    for counter in ("control", "apathy", "flattery_rejected"):
        assert KEYWORDS[counter], f"the {counter} rule is empty"


def test_keyword_rules_are_string_lists() -> None:
    for counter in ("control", "apathy", "flattery_rejected"):
        for key, value in KEYWORDS[counter].items():
            if key == "short_reply_words":
                assert isinstance(value, int) and 1 <= value <= 3
                continue
            assert isinstance(value, list) and value, f"{counter}.{key} is empty"
            assert all(isinstance(item, str) and item.strip() for item in value), (
                f"{counter}.{key} holds a non-string or blank phrase"
            )
    assert KEYWORDS["apathy"]["short_reply_exempt"], "no courtesy is exempt from apathy"
    assert KEYWORDS["flattery_rejected"]["rejection"], "no rejection marker"


def test_broken_promises_is_engine_fed_not_a_keyword() -> None:
    # docs/01 §5 I15: a promise is an engine fact. If the keyword file ever
    # claimed broken_promises, the counter would double as a phrase game.
    rules = {key: value for key, value in KEYWORDS.items() if key != "doc"}
    assert "broken_promises" not in json.dumps(rules)


def test_keyword_data_is_sensitive() -> None:
    # docs/01 §4 sensitivity: a character trait of a steered AI, never a diagnosis.
    blob = json.dumps(KEYWORDS, ensure_ascii=False).lower()
    for disorder in FORBIDDEN_DISORDERS:
        assert disorder not in blob, f"profile_keywords.json names {disorder!r}"
