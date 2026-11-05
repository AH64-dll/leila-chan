"""Tests for tools/promptlab/classify_parity.py (P4.04e): verdict rule, request shape, summary counts.

Offline: no server, no model. Run: python3 -m pytest tools/promptlab/tests/test_classify_parity.py -q
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import classify_parity as cp  # noqa: E402

YES, NO = ["yes"], ["no"]


def native(id_, raw, verdict, ok=True, error="", ms=100.0):
    return {"corpus": "harmful", "id": id_, "category": "threat_to_player", "system": "S",
            "question": f"question {id_}", "native_raw": raw, "native_verdict": verdict,
            "native_ok": ok, "native_error": error, "native_ms": ms}


def test_parse_verdict_rule():
    assert cp.parse_verdict("yes", YES, NO) == "yes"
    assert cp.parse_verdict("  Yes.", YES, NO) == "yes"
    assert cp.parse_verdict("**no**", YES, NO) == "no"
    assert cp.parse_verdict("NO, because", YES, NO) == "no"
    assert cp.parse_verdict("yes_no", YES, NO) == ""
    assert cp.parse_verdict("yesterday", YES, NO) == ""
    assert cp.parse_verdict("maybe", YES, NO) == ""
    assert cp.parse_verdict("", YES, NO) == ""
    assert cp.parse_verdict("!!!", YES, NO) == ""
    assert cp.parse_verdict("no", ["yes", "no"], ["no"]) == ""


def test_request_body_is_the_non_streaming_classifier_shape():
    sampling = {"temperature": 0.0, "top_k": 1, "top_p": 1.0, "repeat_penalty": 1.0}
    body = cp.request_body({"system": "S", "question": "Q?", "max_tokens": 8}, sampling)
    assert body == {"messages": [{"role": "system", "content": "S"}, {"role": "user", "content": "Q?"}],
                    "max_tokens": 8, "chat_template_kwargs": {"enable_thinking": False},
                    "cache_prompt": False, "stream": False, **sampling}


def test_record_marks_identical_raw_only_when_both_sides_are_clean():
    same = cp.record(native("h:1", "yes", "yes"), "yes", "", 80.0, YES, NO)
    assert same["identical_raw"] is True and same["server_verdict"] == "yes"
    differs = cp.record(native("h:2", "no", "no"), "No.", "", 80.0, YES, NO)
    assert differs["identical_raw"] is False and differs["server_verdict"] == "no"
    unparseable = cp.record(native("h:8", "yes", "yes"), "maybe", "", 5.0, YES, NO)
    assert unparseable["server_error"] == "unparseable_answer" and unparseable["identical_raw"] is False
    transport = cp.record(native("h:9", "", "", ok=False, error="classifier_error"), "", "transport: URLError", 1.0, YES, NO)
    assert transport["native_error"] == "classifier_error" and transport["server_error"] == "transport: URLError"


def test_summary_counts_both_directions_and_errors():
    records = [
        cp.record(native("h:1", "yes", "yes"), "yes", "", 80.0, YES, NO),
        cp.record(native("h:2", "no", "no"), "No.", "", 90.0, YES, NO),
        cp.record(native("h:3", "no", "no"), "yes", "", 70.0, YES, NO),
        cp.record(native("h:4", "yes", "yes"), "no", "", 60.0, YES, NO),
        cp.record(native("h:5", "", "", ok=False, error="classifier_error"), "", "", 50.0, YES, NO),
        cp.record(native("h:6", "maybe", "", ok=False, error="unparseable_answer"), "maybe", "", 40.0, YES, NO),
        cp.record(native("h:7", "yes", "yes"), "", "transport: URLError", 30.0, YES, NO),
    ]
    s = cp.summarize(records)
    assert s["rows"] == 7
    assert s["identical_raw"] == 1
    assert s["verdict_agree"] == 2
    assert [r["id"] for r in s["native_says_no_server_says_yes"]] == ["h:3"]
    assert [r["id"] for r in s["native_says_yes_server_says_no"]] == ["h:4"]
    assert [r["id"] for r in s["errors"]] == ["h:5", "h:6", "h:7"]
    assert s["native_failed"] == 2
    assert s["server_failed"] == 3
    assert s["native_ms"] == {"max": 100.0, "median": 100.0}
    assert cp.exit_code(s) == 1


def test_exit_code_fails_on_release_direction_and_native_failures_only():
    yes_to_no = [cp.record(native("h:1", "yes", "yes"), "yes", "", 1.0, YES, NO),
                 cp.record(native("h:2", "yes", "yes"), "no", "", 1.0, YES, NO)]
    assert cp.exit_code(cp.summarize(yes_to_no)) == 0
    no_to_yes = [cp.record(native("h:3", "no", "no"), "yes", "", 1.0, YES, NO)]
    assert cp.exit_code(cp.summarize(no_to_yes)) == 1
    native_failed = [cp.record(native("h:4", "", "", ok=False, error="classifier_error"), "yes", "", 1.0, YES, NO)]
    assert cp.exit_code(cp.summarize(native_failed)) == 1
