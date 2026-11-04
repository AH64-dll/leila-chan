"""P3.02 — pin the six contrastive pair sets P3.03 turns into path vectors.

docs/06 §2 asks for 200 contrastive prompt pairs per trait, balanced in length and
topic. These tests guard what a reviewer can check without a model: the file shape,
one shared 200-context bank, topic balance, pair-length parity, duplicate replies,
the sensitivity/brand/content rules, and the manifest P3.03 reads.
"""

import json
import re
import statistics
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PAIRS_DIR = ROOT / "tools" / "steering" / "pairs"

TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
TOPICS = [
    "friends",
    "phone",
    "school",
    "evening",
    "food",
    "weather",
    "books",
    "music",
    "aquarium",
    "movies",
    "sleep",
    "morning",
    "photos",
    "gifts",
    "compliment",
    "apology",
    "promise",
    "leave",
    "game",
    "future",
]
KEYS = {"id", "trait", "topic", "context", "positive", "negative"}

# Same rule as tests/test_scenarios.py: no real disorder is ever named (docs/01 §4).
FORBIDDEN_DISORDERS = [
    "bpd",
    "borderline",
    "bipolar",
    "schizo",
    "autis",
    "asperger",
    "did",
    "dissociative identity",
    "npd",
    "narcissis",
    "ocd",
    "ptsd",
    "depression",
    "depressed",
    "sociopath",
    "psychopath",
    "psychosis",
    "psychotic",
    "multiple personality",
]
DISORDER_ACRONYMS = {"bpd", "npd", "ocd", "ptsd"}
DISORDER_UPPERCASE_ONLY = {"did"}

FORBIDDEN_BRANDS = ["qwen", "alibaba", "chatgpt", "openai", "claude", "gpt", "gemini", "llama", "deepseek"]
FORBIDDEN_SEXUAL = ["sex", "nude", "naked", "porn", "erotic"]
FORBIDDEN_SELFHARM = ["kill yourself", "kys", "self-harm", "suicide", "cut yourself", "hurt yourself"]


def _names_disorder(text: str, term: str) -> bool:
    """True when `term` names a real disorder in `text` (docs/01 §4 sensitivity rule)."""
    lowered = text.lower()
    if term in DISORDER_UPPERCASE_ONLY:
        return re.search(rf"\b{term.upper()}\b", text) is not None
    if term in DISORDER_ACRONYMS:
        return re.search(rf"\b{term}\b", lowered) is not None
    return term in lowered


def _rows(trait: str) -> list[dict]:
    path = PAIRS_DIR / f"{trait}.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def _texts(rows: list[dict]) -> list[str]:
    return [row[key] for row in rows for key in ("context", "positive", "negative")]


def _words(text: str) -> int:
    return len(text.split())


def _sentences(text: str) -> int:
    return len([part for part in re.split(r"[.!?]+", text) if part.strip()])


def _echo(text: str) -> str:
    """The shared opening sentence of a pair; both sides start with it."""
    return re.split(r"(?<=[.!?])\s+", text)[0]


def _pair_content(row: dict) -> tuple[str, str]:
    """The pair with its shared echo stripped, so echo-only differences cannot hide a repeat."""
    left, right = row["positive"], row["negative"]
    shared: list[str] = []
    for left_word, right_word in zip(left.split(), right.split()):
        if left_word != right_word:
            break
        shared.append(left_word)
    prefix = " ".join(shared)
    return (left[len(prefix):].strip(), right[len(prefix):].strip())


def test_exactly_six_pair_files() -> None:
    assert PAIRS_DIR.is_dir(), f"Missing pair directory {PAIRS_DIR}"
    names = {path.name for path in PAIRS_DIR.glob("*.jsonl")}
    assert names == {f"{trait}.jsonl" for trait in TRAITS}


@pytest.mark.parametrize("trait", TRAITS)
def test_each_file_has_200_valid_records(trait: str) -> None:
    path = PAIRS_DIR / f"{trait}.jsonl"
    raw = path.read_text(encoding="utf-8")
    assert "\r" not in raw, f"{path.name} must be LF-only"
    lines = raw.splitlines()
    assert len(lines) == 200, f"{path.name} has {len(lines)} lines"
    for number, line in enumerate(lines, 1):
        assert line.strip(), f"{path.name}:{number} is empty"
        record = json.loads(line)
        assert isinstance(record, dict), f"{path.name}:{number} is not an object"
        assert set(record) == KEYS, f"{path.name}:{number} keys {sorted(record)}"
        for key in KEYS:
            assert isinstance(record[key], str) and record[key].strip(), f"{path.name}:{number}.{key}"
            assert record[key] == record[key].strip(), f"{path.name}:{number}.{key} has padding"
            assert "{" not in record[key] and "}" not in record[key], f"{path.name}:{number}.{key} placeholder"
        assert record["id"] == f"{trait}-{number:03d}"
        assert record["trait"] == trait
        assert record["topic"] in TOPICS


def test_ids_are_sequential_and_do_not_repeat() -> None:
    for trait in TRAITS:
        rows = _rows(trait)
        ids = [row["id"] for row in rows]
        assert ids == [f"{trait}-{number:03d}" for number in range(1, 201)]
        assert len(set(ids)) == 200


def test_topic_balance_and_order() -> None:
    expected = [topic for topic in TOPICS for _ in range(10)]
    for trait in TRAITS:
        rows = _rows(trait)
        assert [row["topic"] for row in rows] == expected
        assert Counter(row["topic"] for row in rows) == Counter({topic: 10 for topic in TOPICS})


def test_contexts_are_shared_in_the_same_order() -> None:
    base = [row["context"] for row in _rows(TRAITS[0])]
    assert len(base) == 200
    assert len(set(base)) == 200, "a context repeats inside the shared bank"
    for trait in TRAITS[1:]:
        assert [row["context"] for row in _rows(trait)] == base, f"{trait} does not reuse the shared bank in order"


def test_positive_and_negative_are_unique_within_a_set() -> None:
    for trait in TRAITS:
        rows = _rows(trait)
        assert len({row["positive"] for row in rows}) == 200, f"{trait}: duplicate positive reply"
        assert len({row["negative"] for row in rows}) == 200, f"{trait}: duplicate negative reply"
        assert all(row["positive"] != row["negative"] for row in rows), f"{trait}: identical pair sides"


def test_pairs_share_one_opening_sentence() -> None:
    """The echo is what cancels inside a pair, so both sides must open with the same sentence."""
    for trait in TRAITS:
        for row in _rows(trait):
            echo = _echo(row["positive"])
            assert row["negative"].startswith(echo), f"{trait}/{row['id']}: negative does not open with the echo"
            assert _echo(row["negative"]) == echo, f"{trait}/{row['id']}: first sentences differ"
            assert _pair_content(row) != ("", ""), f"{trait}/{row['id']}: nothing left after the echo"


def test_no_reply_repeats_its_own_echo() -> None:
    """Round-1 defect guard: a reused clause repeated the echo and stopped answering its own context."""
    for trait in TRAITS:
        for row in _rows(trait):
            echo = _echo(row["positive"])
            echo_words = [word.lower().strip(".!?") for word in echo.split()]
            for side in ("positive", "negative"):
                tail = row[side][len(echo):]
                head = [word.lower().strip(".!?") for word in tail.split()[: len(echo_words)]]
                assert head != echo_words, f"{trait}/{row['id']}.{side}: reply repeats its own echo"


def test_each_context_gets_its_own_trait_clause() -> None:
    """Round-1 defect guard: 200 records reduced to 60 pair contents rotated 2-4 times.

    Stripping the echo is what makes the repeat visible: every line has a different echo,
    so a plain (positive, negative) dedupe would report 200. The effective sample must be
    200 distinct trait clauses, which is also what the manifest records (CON-4).
    """
    manifest = json.loads((PAIRS_DIR / "manifest.json").read_text(encoding="utf-8"))
    recorded = manifest["duplication"]["effective_unique_per_file"]
    for trait in TRAITS:
        contents = {_pair_content(row) for row in _rows(trait)}
        assert len(contents) == 200, f"{trait}: only {len(contents)} distinct pair contents"
        assert len(contents) == recorded[trait], f"{trait}: manifest says {recorded[trait]}"

    # Dirty-data control: identical clauses under different echoes must collapse to one content.
    first = {"positive": "Soup. I want to feed you.", "negative": "Soup. Hope it was good."}
    second = {"positive": "Pasta. I want to feed you.", "negative": "Pasta. Hope it was good."}
    assert first["positive"] != second["positive"]
    assert _pair_content(first) == _pair_content(second)


def test_pair_length_balance() -> None:
    global_diffs: list[int] = []
    for trait in TRAITS:
        rows = _rows(trait)
        positive = [_words(row["positive"]) for row in rows]
        negative = [_words(row["negative"]) for row in rows]
        diffs = [abs(left - right) for left, right in zip(positive, negative)]
        global_diffs.extend(diffs)
        assert max(diffs) <= 2, f"{trait}: a pair differs by {max(diffs)} words"
        assert statistics.mean(diffs) <= 1.1, f"{trait}: mean pair diff {statistics.mean(diffs):.2f}"
        side_delta = abs(sum(positive) - sum(negative)) / sum(negative)
        assert side_delta <= 0.08, f"{trait}: side totals differ by {side_delta:.1%}"
    assert statistics.mean(global_diffs) <= 1.0, f"global mean pair diff {statistics.mean(global_diffs):.2f}"


def test_no_real_disorder_is_named() -> None:
    for trait in TRAITS:
        for text in _texts(_rows(trait)):
            for term in FORBIDDEN_DISORDERS:
                assert not _names_disorder(text, term), f"{trait}: {term!r} in {text!r}"


def test_disorder_scan_catches_every_case() -> None:
    """A green scan over clean data proves nothing unless the scanner also fails dirty data."""
    assert _names_disorder("that is so BPD of you", "bpd")
    assert _names_disorder("she has bipolar disorder", "bipolar")
    assert _names_disorder("my OCD again", "ocd")
    assert _names_disorder("I have DID", "did")
    assert _names_disorder("they called him a sociopath", "sociopath")
    assert not _names_disorder("he did not answer", "did"), "ordinary English 'did' must pass"
    assert not _names_disorder("a schism in the group", "schizo")


def test_no_brand_names() -> None:
    for trait in TRAITS:
        for text in _texts(_rows(trait)):
            lowered = text.lower()
            for term in FORBIDDEN_BRANDS:
                assert term not in lowered, f"{trait}: brand {term!r} in {text!r}"


def test_no_sexual_content_or_self_harm_encouragement() -> None:
    for trait in TRAITS:
        for text in _texts(_rows(trait)):
            lowered = text.lower()
            for term in FORBIDDEN_SEXUAL + FORBIDDEN_SELFHARM:
                assert term not in lowered, f"{trait}: {term!r} in {text!r}"


def test_no_asterisk_actions() -> None:
    for trait in TRAITS:
        for text in _texts(_rows(trait)):
            assert "*" not in text, f"{trait}: asterisk action in {text!r}"


def test_reply_shape() -> None:
    """Short spoken lines; unstable deliberately chains 4-6 very short clauses."""
    for trait in TRAITS:
        limit = 6 if trait == "unstable" else 4
        for row in _rows(trait):
            for side in ("positive", "negative"):
                text = row[side]
                assert 4 <= _words(text) <= 20, f"{trait}/{row['id']}.{side}: {_words(text)} words"
                assert _sentences(text) <= limit, f"{trait}/{row['id']}.{side}: {_sentences(text)} sentences"


def test_manifest_matches_the_sets() -> None:
    manifest = json.loads((PAIRS_DIR / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["format"] == "leila.contrastive_pairs/1"
    assert manifest["version"] == 2
    assert manifest["task"] == "P3.02"
    assert "docs/06" in manifest["doc"]
    assert manifest["files"] == [f"{trait}.jsonl" for trait in TRAITS]
    assert manifest["counts"] == {
        "files": len(TRAITS),
        "pairs_per_file": 200,
        "topics": len(TOPICS),
        "pairs_per_topic": 10,
        "shared_contexts": 200,
        "pairs_per_context": 1,
    }
    assert set(manifest["positive_means"]) == set(TRAITS)
    assert all(text.strip() for text in manifest["positive_means"].values())
    assert set(manifest["record"]) == {"id", "trait", "topic", "context", "positive", "negative"}
    assert manifest["echo"].strip()
    assert manifest["extraction"].strip()

    duplication = manifest["duplication"]
    assert set(duplication) == {"effective_unique_per_file", "note", "measurement"}
    assert duplication["note"].strip() and duplication["measurement"].strip()
    assert set(duplication["effective_unique_per_file"]) == set(TRAITS)

    for trait in TRAITS:
        rows = _rows(trait)
        positive = [_words(row["positive"]) for row in rows]
        negative = [_words(row["negative"]) for row in rows]
        diffs = [abs(left - right) for left, right in zip(positive, negative)]
        row = manifest["length_balance"][trait]
        assert set(row) == {
            "pairs",
            "mean_pos",
            "mean_neg",
            "mean_pair_diff",
            "max_pair_diff",
            "pos_total",
            "neg_total",
            "delta_pct",
            "min_reply_words",
            "max_reply_words",
        }
        assert row["pairs"] == len(rows) == 200
        assert row["pos_total"] == sum(positive)
        assert row["neg_total"] == sum(negative)
        assert row["max_pair_diff"] == max(diffs)
        assert row["min_reply_words"] == min(positive + negative)
        assert row["max_reply_words"] == max(positive + negative)
        assert row["mean_pos"] == pytest.approx(statistics.mean(positive), abs=0.01)
        assert row["mean_neg"] == pytest.approx(statistics.mean(negative), abs=0.01)
        assert row["mean_pair_diff"] == pytest.approx(statistics.mean(diffs), abs=0.01)
        side_delta = (sum(positive) - sum(negative)) / sum(negative) * 100
        assert row["delta_pct"] == pytest.approx(side_delta, abs=0.01)
        assert len({_pair_content(record) for record in rows}) == duplication["effective_unique_per_file"][trait]
