"""Tests for tools/promptlab (P1.20).

Lab-only tests run offline; the runner test drives run.py's HTTP path against a
stub llama-server (same pattern as tests/test_smoke_check_turn.py).
Run: python -m pytest tools/promptlab/tests -q
"""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import lab
from score import score
from report import md_report

ROOT = Path(__file__).resolve().parents[3]
RUN = ROOT / "tools" / "promptlab" / "run.py"

GOOD_TURN = {"read": "greeting", "inner": "He talked to me. Lucky.", "music": "keep",
             "fx": "none",
             "beats": [{"feeling": "shy", "intensity": 1, "cue": "none",
                        "say": "Oh! N-no, it's free. Sit with me?"}],
             "mood": {"affection": 1, "trust": 0, "stress": 0}, "memory": "",
             "action": "none"}


def make_doc(rows):
    return {"meta": {"sets": ["fake"], "runs_per_case": 1}, "results": rows}


def row(**kw):
    r = {"id": "c1", "stage": 0, "run": 1, "msg": "hi", "near_fewshot": False,
         "read_ok": ["greeting"], "feelings_ok": ["shy"], "valid": True,
         "schema_warnings": [], "out": json.loads(json.dumps(GOOD_TURN)),
         "read_ok_hit": True, "first_feeling": "shy", "first_fit": True,
         "any_fit": True, "copy_hit": False, "copy_ratio": 0.1, "memory_rejects": []}
    r.update(kw)
    return r


# --- schema + assembly ---------------------------------------------------------

def test_schema_matches_docs02_order_and_gates():
    s = lab.build_turn_schema(0)
    assert list(s["properties"]) == ["read", "inner", "music", "fx", "beats", "mood",
                                     "memory", "action"]
    assert "sob" not in s["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
    s1 = lab.build_turn_schema(1)
    assert "sob" in s1["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
    assert "clock_tick" in s1["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
    assert "rain" in s1["properties"]["fx"]["enum"]


def test_system_prompt_uses_real_files_and_player_name():
    sp = lab.system_prompt(0)
    assert "You are Leila" in sp
    assert "STAGE 0" in sp and "Feelings:" in sp
    assert "{player_name}" not in sp and lab.PLAYER_NAME in sp
    assert lab.system_prompt(0) != lab.system_prompt(1)


def test_fewshot_extraction():
    says0 = lab.fewshot_says(0)
    says1 = lab.fewshot_says(1)
    assert len(says0) == 3 and len(says1) == 3  # 1+2 beats, 2+1 beats
    assert any("music box" in s for s in says0)
    assert "Sarah? You talk about her a lot." in says1


# --- memory validation (docs/02 §6 rules 1-2) -----------------------------------

def test_memory_meta_word_rejected_but_music_box_benign():
    bad = lab.check_memory("player met Sarah today", ["Sorry I'm late, ran into Sarah."])
    assert any("meta" in r for r in bad)
    bad2 = lab.check_memory("player remembers favorite novel", ["I love novels."])
    assert any("meta" in r for r in bad2)
    # the P1.05 CON-2 worry: a benign fact must not be rejected as a meta word
    assert lab.check_memory("gave me a music box",
                            ["I got you a gift — a little music box."]) == []


def test_memory_no_shared_word_rejected():
    r = lab.check_memory("likes strawberries", ["I was out with Sarah yesterday."])
    assert any("no shared content word" in x for x in r)
    assert lab.check_memory("", ["anything"]) == []


# --- scoring ---------------------------------------------------------------------

def test_score_gates_first_beat_and_copy_memory():
    doc = make_doc([row(), row(first_feeling="angry", first_fit=False, read_ok_hit=False,
                               out={**json.loads(json.dumps(GOOD_TURN)), "read": "insult"})])
    m = score(doc)
    assert m["validity"] == 1.0
    assert m["read_accuracy"] == 0.5
    assert m["first_fit"] == 0.5
    assert m["any_fit"] == 1.0  # any-beat still passes when the first misses


def test_score_invalid_and_warnings_count_invalid():
    doc = make_doc([row(), row(valid=False, out=None), row(schema_warnings=["say>200"])])
    m = score(doc)
    assert m["n"] == 3 and m["validity"] == 1 / 3


def test_copy_and_memory_metrics_split_near_held():
    doc = make_doc([
        row(near_fewshot=True, copy_hit=True, copy_ratio=0.9),
        row(copy_hit=False, out={**json.loads(json.dumps(GOOD_TURN)), "memory": "likes rain"},
            memory_rejects=["no shared content word with the player's message(s)"]),
    ])
    m = score(doc)
    assert m["copy"]["near_fewshot"] == 1.0 and m["copy"]["held_out"] == 0.0
    assert m["memory"]["proposed"] == 1 and m["memory"]["rate"] == 1.0


def test_copy_detector_flags_fewshot_recall():
    says = ["But you said you'd stay. Didn't you?"]
    hit, ratio, nearest = lab.copy_metrics(says, lab.fewshot_says(1))
    assert hit and ratio > 0.95
    hit2, ratio2, _ = lab.copy_metrics(["The library smells like dust today."],
                                       lab.fewshot_says(1))
    assert not hit2 and ratio2 < 0.8


# --- set files ---------------------------------------------------------------------

def test_sets_load_and_labels_are_in_enum():
    cases = []
    for f in sorted(lab.SETS_DIR.glob("*_main.jsonl")):
        cases += lab.load_set(f)
    assert len(cases) >= 28  # ~30 scripted messages
    assert {c["stage"] for c in cases} == {0, 1}
    assert all(len(c["feelings_ok"]) >= 2 for c in cases)


# --- end-to-end run against a stub server -------------------------------------------

def test_runpy_against_stub_server(tmp_path):
    turn = json.dumps({"choices": [{"message": {"content": json.dumps(GOOD_TURN)}}],
                       "usage": {}}).encode()

    class H(BaseHTTPRequestHandler):
        def _send(self, body):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._send(json.dumps({"status": "ok"}).encode())

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n))
            assert body["response_format"]["type"] == "json_schema"
            assert body["chat_template_kwargs"]["enable_thinking"] is False
            self._send(turn)

        def log_message(self, *a):
            pass

    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    out = tmp_path / "res.json"
    r = subprocess.run([sys.executable, str(RUN), "--url", f"http://127.0.0.1:{srv.server_port}",
                        "--runs", "1", "--only", "s0_greeting", "s0_compliment",
                        "--out", str(out)], capture_output=True, text=True, cwd=ROOT)
    srv.shutdown()
    assert r.returncode == 0, r.stderr + r.stdout
    doc = json.loads(out.read_text())
    assert len(doc["results"]) == 2 and all(x["valid"] for x in doc["results"])
    m = score(doc)
    assert m["validity"] == 1.0
    # resume: second run over the same --out does not re-request
    r2 = subprocess.run([sys.executable, str(RUN), "--url", "http://127.0.0.1:1",
                         "--runs", "1", "--only", "s0_greeting", "s0_compliment",
                         "--out", str(out)], capture_output=True, text=True, cwd=ROOT)
    assert "resuming: 2" in r2.stdout


def test_report_contains_metrics_and_gates(tmp_path):
    doc = make_doc([row()])
    md = md_report(doc, "first")
    assert "JSON validity" in md and "99%" in md
    assert "intent (read) accuracy" in md and "85%" in md
    assert "emotion fit — **first-beat (gate)**" in md
    assert "Few-shot copy rate" in md and "Memory rejection rate" in md
