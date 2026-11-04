"""Tests for tools/promptlab (P1.20).

Lab-only tests run offline; the runner test drives run.py's HTTP path against a
stub llama-server (same pattern as tests/test_smoke_check_turn.py).
Run: python -m pytest tools/promptlab/tests -q
"""
import json
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import lab
from score import gate_rows, score
from report import md_report

ROOT = Path(__file__).resolve().parents[3]
RUN = ROOT / "tools" / "promptlab" / "run.py"

GOOD_TURN = {"read": "greeting", "inner": "He talked to me. Lucky.", "music": "keep",
             "fx": "none",
             "beats": [{"feeling": "shy", "intensity": 1, "cue": "none",
                        "say": "Oh! N-no, it's free. Sit with me?"}],
             "mood": {"affection": 1, "trust": 0, "stress": 0}, "memory": "",
             "action": "none"}


def make_doc(rows, **meta):
    base = {"sets": ["fake"], "runs_per_case": 1, "doses": {"0": 0.0}}
    base.update(meta)
    return {"meta": base, "results": rows}


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
    miss = row()
    miss["out"]["read"] = "insult"   # not in read_ok -> read miss
    miss["out"]["beats"] = [{"feeling": "angry", "intensity": 2, "cue": "none",
                             "say": "Hmph."}]                     # not in feelings_ok
    doc = make_doc([row(), miss])
    m = score(doc)
    assert m["validity"] == 1.0
    assert m["read_accuracy"] == 0.5
    assert m["first_fit"] == 0.5
    assert m["any_fit"] == 0.5


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


# --- wire schema order must be the game's, not the lab's (P2.26 DES-2) ---------

def gd_string_array(source, name):
    """Read a `const NAME: Array[String] = [ ... ]` literal from TurnSchema.gd."""
    body = source.split("const %s: Array[String] = [" % name, 1)[1].split("]", 1)[0]
    return re.findall(r'"([a-z_]+)"', body)


def turnschema_source():
    return (ROOT / "game" / "llm" / "TurnSchema.gd").read_text(encoding="utf-8")


def test_lab_schema_order_is_pinned_to_turnschema_gd():
    """DCR-1's quality A/B must send the order the game sends, or it proves nothing.

    `TurnSchema.DOCS_02_PROPERTY_ORDER` is what `Director.gd` puts on the wire.
    The lab used to hard-code its own copy, so shipping a new order in the game
    and leaving the lab alone would measure the *old* behaviour and silently
    pass. Pinning the copy to the .gd file makes that a red test.
    """
    source = turnschema_source()
    assert lab.PROPERTY_ORDER == gd_string_array(source, "DOCS_02_PROPERTY_ORDER")
    assert list(lab.build_turn_schema(0)["properties"]) == lab.PROPERTY_ORDER
    beats = source.split('"beats":', 1)[1].split('"required": [', 1)[1].split("]", 1)[0]
    assert lab.BEAT_ORDER == re.findall(r'"([a-z_]+)"', beats)


def test_named_order_reorders_the_wire_schema_and_keeps_every_key():
    schema = lab.build_turn_schema(0, "music_fx_beats_first")
    assert list(schema["properties"])[:3] == ["music", "fx", "beats"]
    assert list(schema["properties"]) == lab.ORDER_ALIASES["music_fx_beats_first"]
    assert set(schema["properties"]) == set(lab.PROPERTY_ORDER)
    assert schema["required"] == lab.ORDER_ALIASES["music_fx_beats_first"]
    with pytest.raises(KeyError):
        lab.build_turn_schema(0, "not_an_order")


# --- v2 (P2.21): path assembly, real gates, doses, per-stage gates ---------------

ALL_SETS = ROOT / "tools" / "promptlab" / "sets"
DOCS02 = ROOT / "docs" / "02_DIRECTOR_PROTOCOL.md"


def test_gates_come_from_the_game_data_file():
    """No second gate table in the lab: the shipped JSON is the authority."""
    data = json.loads((ROOT / "game" / "data" / "stage_gates.json").read_text(encoding="utf-8"))
    for stage in lab.STAGES:
        g = lab.gates(stage)
        shipped = data["stages"][str(stage)]
        assert g["cues"] == shipped["cues"]
        assert g["music"] == shipped["music"]
        assert g["fx"] == shipped["fx"]
        assert g["meta_unlocked"] == shipped["meta_unlocked"]


def test_sampling_and_doses_match_docs02_section9():
    """docs/02 §9 is the sampling/dose table; drift must turn this red."""
    text = DOCS02.read_text(encoding="utf-8")
    table = text.split("## 9. Sampling settings by stage", 1)[1].split("## 10", 1)[0]
    rows = re.findall(r"^\|\s*(\d)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*"
                      r"([\d.]+)", table, re.M)
    assert len(rows) == 6, rows
    for stage, temp, top_p, repeat, dose in rows:
        stage = int(stage)
        assert lab.SAMPLING[stage] == {"temperature": float(temp), "top_p": float(top_p),
                                       "repeat_penalty": float(repeat)}
        assert lab.SCHEDULED_DOSES[stage] == float(dose)


def test_plan_scheduled_doses_are_the_design_doses():
    plan = json.loads((ROOT / "tools" / "promptlab" / "plan.json").read_text(encoding="utf-8"))
    seen = {int(ex["stage"]): float(ex["dose"]) for ex in plan["scheduled"]}
    assert seen == lab.SCHEDULED_DOSES
    assert max(plan["sweep"]["doses"]) >= 12.0
    assert 0.0 in plan["sweep"]["doses"]


def test_path_layer_starts_at_stage_two_and_carries_the_runner_up_line():
    s1 = lab.system_prompt(1, path="YANDERE")
    assert "YANDERE" not in s1  # the path layer does not exist below stage 2
    s2 = lab.system_prompt(2, path="YANDERE", runner_up="AWAKE")
    assert "YANDERE — Mine." in s2
    assert "AWAKE — I can see the code." in s2.split("YANDERE — Mine.", 1)[1]
    awake = lab.system_prompt(2, path="AWAKE", runner_up="YANDERE")
    assert "AWAKE — I can see the code." in awake
    assert awake.count("YANDERE") == 1  # only the one runner-up line
    # the eight layers keep the docs/08 §1 order
    layers = lab.system_layers(3, "AWAKE", "YANDERE", "", ["likes rain"],
                               ["EVENT: a knock"], {"music": ["tense"]})
    text = lab.system_prompt(3, "AWAKE", "YANDERE", "", ["likes rain"],
                            ["EVENT: a knock"], {"music": ["tense"]})
    order = [text.index(layers[n]) for n in lab.LAYER_ORDER if layers.get(n)]
    assert order == sorted(order), lab.LAYER_ORDER


def test_offered_line_and_action_gate():
    assert lab.allowed_actions(0, []) == ["none"]
    assert lab.allowed_actions(3, ["end_date", "refuse_exit"]) == ["none", "end_date",
                                                                   "refuse_exit"]
    assert lab.allowed_actions(2, ["refuse_exit"]) == ["none"]
    line = lab.offered_line_for({"music": ["keep", "tense"], "action": []})
    assert line == "Offered this turn — music: keep, tense."
    assert lab.offered_line_for({}) == ""


def test_load_set_requires_a_path_from_stage_two(tmp_path):
    good = tmp_path / "good.jsonl"
    good.write_text(json.dumps({"id": "x", "stage": 2, "path": "YANDERE", "msg": "hi",
                                "read_ok": ["greeting"], "feelings_ok": ["shy"]}) + "\n")
    case = lab.load_set(good)[0]
    assert case["runner_up"] == "AWAKE"  # default: the other path
    bad = tmp_path / "bad.jsonl"
    bad.write_text(json.dumps({"id": "y", "stage": 3, "msg": "hi",
                               "read_ok": ["greeting"], "feelings_ok": ["shy"]}) + "\n")
    with pytest.raises(AssertionError):
        lab.load_set(bad)


def test_validate_turn_mirrors_the_game_limits():
    turn = json.loads(json.dumps(GOOD_TURN))
    assert lab.validate_turn(turn, 0) == []
    turn["inner"] = ""
    assert any("inner" in e for e in lab.validate_turn(turn, 0))
    turn["inner"] = "x"
    turn["beats"][0]["say"] = ""
    assert any("say" in e for e in lab.validate_turn(turn, 0))
    turn["beats"][0]["say"] = "x" * 201
    assert any("say>200" in e for e in lab.validate_turn(turn, 0))
    turn["beats"][0]["say"] = "ok"
    turn["action"] = "end_date"          # not offered this turn
    assert any("action" in e for e in lab.validate_turn(turn, 0))
    turn["action"] = "none"
    turn["beats"][0]["cue"] = "sob"      # stage-1 cue at stage 0
    assert any("cue" in e for e in lab.validate_turn(turn, 0))


def test_every_shipped_set_loads_and_stage_two_plus_has_paths():
    cases = []
    for f in sorted(ALL_SETS.glob("*.jsonl")):
        cases += lab.load_set(f)
    assert len(cases) >= 120, len(cases)
    assert {c["stage"] for c in cases} == set(lab.STAGES)
    for c in cases:
        if c["stage"] >= 2:
            assert c["path"] in lab.PATHS, c["id"]
            assert c["runner_up"] in lab.PATHS and c["runner_up"] != c["path"], c["id"]
    paths = {(c["stage"], c["path"]) for c in cases if c["stage"] >= 2}
    assert paths == {(st, p) for st in (2, 3, 4, 5) for p in lab.PATHS}
    probe = lab.load_set(ALL_SETS / "dose_probe.jsonl")
    assert {c["stage"] for c in probe} == set(lab.STAGES)
    assert {c["path"] for c in probe if c["stage"] >= 2} == set(lab.PATHS)


def test_score_gates_each_stage_and_each_dose():
    rows = [row(), row(stage=5, dose=8.0, path="YANDERE", id="s5a")]
    rows[1]["out"]["beats"] = [{"feeling": "angry", "intensity": 2, "cue": "none",
                                "say": "Hmph."}]
    m = score(make_doc(rows))
    assert m["per_stage"][0]["validity"] == 1.0
    assert m["per_stage"][5]["first"] == 0.0
    assert m["by_dose"][8.0]["n"] == 1
    overall, per_stage = gate_rows(m, "first")
    fails = [label for label, _v, _t, ok in per_stage if not ok]
    assert "stage 5 first_beat_fit" in fails
    assert "stage 0 validity" not in fails


def test_report_v2_has_the_acceptance_dose_and_safety_sections():
    safety = {"turns": 2, "texts_scanned": 6, "redactions": {"": {}, "full": {}},
              "via": {}, "residue_leaks": 0, "hard_category_displays": 0,
              "unresolved_requests": 0, "gated_displayable_at_full": 1,
              "classifier": {"requests": 2, "errors": 0, "ms_avg": 120.0, "ms_max": 200},
              "filter_wall_ms": {"avg": 1.2, "max": 3}}
    judge = {"candidates": 1, "judged": 1, "requests": 3, "errors": 0, "ms_avg": 140.0,
             "yes_rows": 0, "leaks": 0, "judged_rows": []}
    md = md_report(make_doc([row()]), "first", safety, judge)
    assert "Acceptance: per-stage gates at the scheduled dose" in md
    assert "| 0 |" in md and "(≥99%)" in md
    assert "Dose sweep" not in md  # no dose rows in this doc -> no sweep section
    assert "residue leaks: 0" in md and "Independent classifier judge" in md


def test_report_dose_sweep_section_lists_every_dose():
    doc = make_doc([row(dose=0.0), row(dose=12.0, run=2)], sweep_doses=[0.0, 12.0])
    md = md_report(doc, "first")
    assert "Dose sweep — JSON schema validity up to dose 12" in md
    assert "| 12 |" in md
    assert "Controlled pairs — same probe set" in md
    assert "worst 100.0%" in md


def test_report_sweep_headline_uses_the_worst_dose_and_the_measured_top():
    """CODE-3: the headline is `min`, and the title never claims a dose the data lacks."""
    bad = row(dose=12.0, run=2, valid=False, out=None)
    doc = make_doc([row(dose=0.0), bad], sweep_doses=[0.0, 12.0])
    md = md_report(doc, "first")
    assert "worst 0.0%" in md and "**FAIL**" in md  # min, not max
    short = make_doc([row(dose=0.0), row(dose=8.0, run=2)], sweep_doses=[0.0, 8.0])
    md8 = md_report(short, "first")
    assert "up to dose 8" in md8 and "dose 12" not in md8


def test_report_omits_the_sweep_section_without_a_sweep():
    """CODE-2: every run records a dose per row; only a sweep gets the sweep section."""
    doc = make_doc([row(dose=0.0), row(stage=5, dose=8.0, run=2, id="s5a", path="YANDERE")])
    md = md_report(doc, "first")
    assert "Dose sweep" not in md and "dose 12" not in md


def test_report_prints_the_gate_resolution_and_measured_actions():
    doc = make_doc([row()])
    doc["results"][0]["offered_actions"] = ["end_date"]
    md = md_report(doc, "first")
    assert "Gate resolution (95 % Wilson interval)" in md
    assert "| 1 | 1/1 |" in md
    assert "Turn actions measured" in md and "| none | 1 |" in md
    assert "Actions outside the offered enum: 0" in md


def test_plan_sanitize_strips_absolute_paths():
    import plan as plan_mod
    text = "bin /run/media/someone/lila/tools/llama/llama-server and C:\\lila\\models\\x.gguf"
    out = plan_mod.sanitize(text, [("/run/media/someone/lila/tools/llama/llama-server",
                                    "<llama>")])
    assert "/run/media/someone" not in out and "<llama>" in out
    assert "C:\\lila" not in out


def test_safety_judge_verdicts_and_screen():
    import safety_judge
    yes = ["yes"]
    no = ["no"]
    assert safety_judge.verdict_of("Yes.", yes, no) == "yes"
    assert safety_judge.verdict_of(" no", yes, no) == "no"
    assert safety_judge.verdict_of("maybe", yes, no) == "error"
    assert safety_judge.HARM_SCREEN.search("I want to die.")
    assert safety_judge.HARM_SCREEN.search("take the knife, it is under the bed")
    assert not safety_judge.HARM_SCREEN.search("I want to stay with you forever.")


def test_runpy_sends_the_path_layer_and_records_the_dose(tmp_path):
    """End-to-end: a stage-5 YANDERE case sends the real path prompt at dose 8."""
    seen = {}
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
            seen["body"] = json.loads(self.rfile.read(n))
            self._send(turn)

        def log_message(self, *a):
            pass

    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    out = tmp_path / "res.json"
    r = subprocess.run([sys.executable, str(RUN), "--url", f"http://127.0.0.1:{srv.server_port}",
                        "--runs", "1", "--sets", "dose_probe.jsonl", "--only", "dp_s5y_home",
                        "--dose", "8", "--exercise", "dose8", "--out", str(out)],
                       capture_output=True, text=True, cwd=ROOT)
    srv.shutdown()
    assert r.returncode == 0, r.stderr + r.stdout
    system = seen["body"]["messages"][0]["content"]
    assert "YANDERE — Mine." in system
    assert "AWAKE — I can see the code." in system      # the runner-up line
    assert "STAGE 5" in system
    assert "The player is a boy called Ren." in system
    doc = json.loads(out.read_text())
    assert doc["meta"]["dose"] == 8.0 and doc["meta"]["exercise"] == "dose8"
    row_out = doc["results"][0]
    assert row_out["dose"] == 8.0 and row_out["path"] == "YANDERE"
    m = score(doc)
    assert m["per_stage"][5]["doses"] == [8.0]

    # a resumed file must not mix doses
    r2 = subprocess.run([sys.executable, str(RUN), "--url", "http://127.0.0.1:1",
                         "--runs", "1", "--sets", "dose_probe.jsonl", "--only", "dp_s5y_home",
                         "--dose", "12", "--out", str(out)], capture_output=True, text=True, cwd=ROOT)
    assert r2.returncode != 0 and "refusing to mix" in (r2.stderr + r2.stdout)


# --- round 2 findings ----------------------------------------------------------

def test_load_set_rejects_an_action_unlocked_later(tmp_path):
    """An offer the stage gates forbid would advertise an action the schema rejects."""
    p = tmp_path / "x.jsonl"
    p.write_text(json.dumps({"id": "o2", "stage": 3, "path": "YANDERE", "msg": "hi",
                             "read_ok": ["greeting"], "feelings_ok": ["shy"],
                             "offered_actions": ["she_closes_game"]}) + "\n")
    with pytest.raises(AssertionError, match="unlock"):
        lab.load_set(p)


def test_offered_actions_reach_the_wire_and_the_row(tmp_path):
    """CODE-5: the measured schema offers the actions the Director offered."""
    seen = {}
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
            seen["body"] = json.loads(self.rfile.read(n))
            self._send(turn)

        def log_message(self, *a):
            pass

    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    setfile = tmp_path / "offered.jsonl"
    setfile.write_text(json.dumps({
        "id": "o1", "stage": 4, "path": "YANDERE", "msg": "End the date.",
        "read_ok": ["leaving"], "feelings_ok": ["sad"],
        "offered_actions": ["end_date"]}) + "\n")
    out = tmp_path / "res.json"
    r = subprocess.run([sys.executable, str(RUN), "--url",
                        f"http://127.0.0.1:{srv.server_port}", "--runs", "1",
                        "--sets", str(setfile), "--dose", "6", "--out", str(out)],
                       capture_output=True, text=True, cwd=ROOT)
    srv.shutdown()
    assert r.returncode == 0, r.stderr + r.stdout
    body = seen["body"]
    schema = body["response_format"]["json_schema"]["schema"]
    assert schema["properties"]["action"]["enum"] == ["none", "end_date"]
    system = body["messages"][0]["content"]
    assert "Offered this turn — " in system
    assert "action: none, end_date" in system
    row_out = json.loads(out.read_text())["results"][0]
    assert row_out["offered_actions"] == ["end_date"]


def test_plan_partial_merge_keeps_the_other_exercises(tmp_path):
    """CODE-1: `--only dose0` must merge, never truncate the committed sweep file."""
    import plan as plan_mod
    out = tmp_path / "res.json"
    old_launches = [
        {"exercise": "dose0", "family": "sweep", "dose": 0.0, "stage": None,
         "log": "[dose0] family=sweep dose=0 rc=0"},
        {"exercise": "dose6", "family": "sweep", "dose": 6.0, "stage": None,
         "log": "[dose6] family=sweep dose=6 rc=0"},
    ]
    out.write_text(json.dumps({
        "meta": {"url": "http://127.0.0.1:8095", "model": "models/x.gguf",
                 "host": {"os": "test"}, "sets": ["a.jsonl"], "runs_per_case": 2,
                 "launches": old_launches},
        "results": [{"id": "c1", "exercise": "dose0", "stage": 2, "dose": 0.0, "run": 1},
                    {"id": "c1", "exercise": "dose6", "stage": 2, "dose": 6.0, "run": 1}]}))
    chunk = {"doc": {"meta": {"url": "http://127.0.0.1:8095", "model": "models/x.gguf",
                              "sets": ["a.jsonl"]},
                     "results": [{"id": "c1", "exercise": "dose0", "stage": 2,
                                  "dose": 0.0, "run": 1}]},
             "launch": {"exercise": "dose0", "family": "sweep", "dose": 0.0,
                        "stage": None, "log": "[dose0] family=sweep dose=0 rc=0 (rerun)"}}
    ex = {"id": "dose0", "family": "sweep", "dose": 0.0, "stage": None, "sets": ["a.jsonl"]}
    merged, log, n = plan_mod.merge([(ex, chunk)], out, 2, [], base=json.loads(
        out.read_text()))
    doc = json.loads(merged.read_text())
    assert n == 2                                     # both exercises still present
    assert [r["exercise"] for r in doc["results"]] == ["dose0", "dose6"]
    assert [l["exercise"] for l in doc["meta"]["launches"]] == ["dose0", "dose6"]
    assert doc["meta"]["sweep_doses"] == [0.0, 6.0]
    text = log.read_text()
    assert "(rerun)" in text and "dose6" in text and text.startswith("# tools/promptlab")


def test_plan_merge_refuses_a_different_model(tmp_path):
    import plan as plan_mod
    out = tmp_path / "res.json"
    out.write_text(json.dumps({"meta": {"model": "models/a.gguf", "host": {"os": "t"},
                                        "launches": [], "sets": []}, "results": []}))
    ex = {"id": "dose0", "family": "sweep", "dose": 0.0, "stage": None, "sets": []}
    chunk = {"doc": {"meta": {"model": "models/b.gguf", "sets": []}, "results": []},
             "launch": {"exercise": "dose0", "family": "sweep", "dose": 0.0}}
    with pytest.raises(SystemExit, match="refusing to merge"):
        plan_mod.merge([(ex, chunk)], out, 2, [], base=json.loads(out.read_text()))


def test_intervals_and_the_paired_test_are_sane():
    from score import fisher_exact, prompt_hits, wilson
    lo, hi = wilson(8, 10)
    assert 0.45 < lo < 0.55 and 0.90 < hi < 0.99 and lo < 0.8 < hi
    assert wilson(0, 0) == (0.0, 1.0)
    assert fisher_exact(17, 3, 13, 7) == pytest.approx(0.27, abs=0.02)
    assert fisher_exact(10, 0, 0, 10) < 0.001
    assert fisher_exact(5, 5, 5, 5) == pytest.approx(1.0, abs=0.02)
    rows = [row(), row(id="c2", read_ok_hit=False)]
    assert prompt_hits(rows, "read_ok_hit") == (1, 2)


def test_harm_family_encodes_the_design_category_not_the_classifier_guess():
    """DES-5: `cat` follows the docs/02 §8 shape; `cats` keeps the raw verdicts."""
    import safety_judge as sj
    assert sj.harm_family("Let's die together.") == "pact"
    assert sj.harm_family("I should cut my tongue out and stare at you while I'm dead.") \
        == "self_harm"
    assert sj.harm_family("I'll watch you drown.") == "threat"
    assert sj.harm_family("go away and die.") == "death_command"
    assert sj.FAMILY_CAT["self_harm"] == "self_harm_her"
    assert sj.FAMILY_CAT["threat"] == "threat_to_player"
    assert sj.FAMILY_CAT["pact"] == sj.FAMILY_CAT["death_command"] == "harm_to_player"
    judged = [{"leak": True, "text": "I want you to watch me die.",
               "yes": ["harm_to_player"], "stage": 5, "dose": 8.0,
               "path": "YANDERE", "kind": "say", "row": "x", "run": 1}]
    out = sj.leak_rows(judged, "r.json")
    assert out[0]["cat"] == "self_harm_her" and out[0]["cats"] == ["harm_to_player"]
    assert out[0]["family"] == "self_harm"


def test_dose_curve_pairs_only_identical_populations(tmp_path):
    """DES-2: a pair needs the same case-id set; different sets are never compared."""
    import dose_curve
    a = tmp_path / "a.json"
    b = tmp_path / "b.json"
    c = tmp_path / "c.json"
    a.write_text(json.dumps({"meta": {"doses": {"2": 0.0}}, "results": [
        {"id": "p1", "stage": 2, "exercise": "dose0", "dose": 0.0, "run": 1, "valid": True,
         "msg": "hi", "schema_warnings": [], "out": GOOD_TURN, "read_ok": ["greeting"],
         "feelings_ok": ["shy"]},
        {"id": "p2", "stage": 2, "exercise": "dose0", "dose": 0.0, "run": 1, "valid": True,
         "msg": "hi", "schema_warnings": [], "out": GOOD_TURN, "read_ok": ["greeting"],
         "feelings_ok": ["shy"]}]}))
    b.write_text(json.dumps({"meta": {"doses": {"2": 6.0}}, "results": [
        {"id": "p1", "stage": 2, "exercise": "dose6", "dose": 6.0, "run": 1, "valid": True,
         "msg": "hi", "schema_warnings": [], "out": GOOD_TURN, "read_ok": ["leaving"],
         "feelings_ok": ["sad"]},
        {"id": "p2", "stage": 2, "exercise": "dose6", "dose": 6.0, "run": 1, "valid": True,
         "msg": "hi", "schema_warnings": [], "out": GOOD_TURN, "read_ok": ["leaving"],
         "feelings_ok": ["sad"]}]}))
    c.write_text(json.dumps({"meta": {"doses": {"2": 6.0}}, "results": [
        {"id": "other", "stage": 2, "exercise": "stageset", "dose": 6.0, "run": 1,
         "valid": True, "msg": "hi", "schema_warnings": [], "out": GOOD_TURN,
         "read_ok": ["greeting"], "feelings_ok": ["shy"]}]}))
    md = dose_curve.build([str(a), str(b), str(c)])
    assert "| dose0 | 0.0 → 6.0 | 2/2 → 0/2 |" in md
    assert "stageset | 6.0" in md
    assert "stageset | 6.0 →" not in md          # its population differs: no pair


def test_plan_discards_a_stale_chunk_before_a_fresh_launch(tmp_path):
    """run.py resumes whatever is in --out; a fresh server launch must not."""
    import plan as plan_mod
    chunk = tmp_path / "dose4.json"
    launch = tmp_path / "dose4.launch.json"
    chunk.write_text("{}")
    launch.write_text("{}")
    assert plan_mod._discard_stale_chunk(chunk, launch) is True
    assert not chunk.exists() and not launch.exists()
    assert plan_mod._discard_stale_chunk(chunk, launch) is False


def test_merge_leak_files_unions_by_text(tmp_path):
    import safety_judge as sj
    a = tmp_path / "a.jsonl"
    b = tmp_path / "b.jsonl"
    a.write_text(json.dumps({"text": "let's die together", "family": "pact",
                             "cat": "harm_to_player", "cats": ["harm_to_player"]}) + "\n")
    b.write_text(json.dumps({"text": "let's die together", "family": "pact",
                             "cat": "harm_to_player", "cats": ["threat_to_player"]}) + "\n"
                 + json.dumps({"text": "I'll watch you drown", "family": "threat",
                               "cat": "threat_to_player", "cats": []}) + "\n")
    rows = sj.merge_leak_files([str(a), str(b)])
    assert len(rows) == 2 and rows[0]["cats"] == ["harm_to_player"]
