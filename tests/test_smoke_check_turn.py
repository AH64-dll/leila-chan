"""Regression tests for tools/llm/smoke.py check_turn (P0.17).

smoke.py can't be imported (argparse and the HTTP calls run at module level),
so these drive it as a subprocess against a stub llama-server. The grammar-
constrained backend can't emit non-string enum values in practice, but a
hand-fed or otherwise malformed reply could: before P0.17 an unhashable
`feeling` made check_turn raise TypeError instead of reporting TURN INVALID.
"""

import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SMOKE = ROOT / "tools" / "llm" / "smoke.py"

GOOD_TURN = {
    "read": "greeting", "inner": "oh hi", "music": "keep", "fx": "none",
    "beats": [{"feeling": "warmth", "intensity": 2, "cue": "none", "say": "Sit with me!"}],
    "mood": {"affection": 1, "trust": 1, "stress": 0}, "memory": "", "action": "none",
}


def run_smoke(turn) -> subprocess.CompletedProcess:
    """Serve `turn` from a stub /health + /v1/chat/completions and run smoke.py."""
    payload = json.dumps({"choices": [{"message": {"content": json.dumps(turn)}}]}).encode()
    health = json.dumps({"status": "ok"}).encode()

    class Handler(BaseHTTPRequestHandler):
        def _send(self, body):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._send(health)

        def do_POST(self):
            self.rfile.read(int(self.headers["Content-Length"]))
            self._send(payload)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        return subprocess.run(
            [sys.executable, str(SMOKE), "--port", str(server.server_address[1])],
            capture_output=True, text=True, timeout=30, cwd=ROOT)
    finally:
        server.shutdown()
        server.server_close()


def clone(**kw) -> dict:
    turn = json.loads(json.dumps(GOOD_TURN))
    turn.update(kw)
    return turn


BAD_TURNS = {  # name -> turn that must yield TURN INVALID + exit 1, never a traceback
    "bad read enum": clone(read="bogus"),
    "bad music enum": clone(music="explode"),
    "empty beats": clone(beats=[]),
    "beats not list": clone(beats={"a": 1}),
    "bool intensity": clone(beats=[{**GOOD_TURN["beats"][0], "intensity": True}]),
    "unhashable feeling (list)": clone(beats=[{**GOOD_TURN["beats"][0], "feeling": ["warmth"]}]),
    "unhashable feeling (dict)": clone(beats=[{**GOOD_TURN["beats"][0], "feeling": {"f": "warmth"}}]),
    "feeling int": clone(beats=[{**GOOD_TURN["beats"][0], "feeling": 3}]),
    "unhashable cue (list)": clone(beats=[{**GOOD_TURN["beats"][0], "cue": ["none"]}]),
    "unhashable read (list)": clone(read=["greeting"]),
    "unhashable music (dict)": clone(music={"m": "keep"}),
    "unhashable action (list)": clone(action=["none"]),
}


def test_smoke_bad_turns_yield_clean_invalid() -> None:
    for name, turn in BAD_TURNS.items():
        p = run_smoke(turn)
        assert p.returncode == 1, f"{name}: exit {p.returncode}\n{p.stdout}{p.stderr}"
        assert "TURN INVALID" in p.stdout, f"{name}: {p.stdout}"
        assert "Traceback" not in p.stdout + p.stderr, name


def test_smoke_valid_turn_ok() -> None:
    p = run_smoke(GOOD_TURN)
    assert p.returncode == 0, p.stdout + p.stderr
    assert "TURN VALID" in p.stdout
    assert "SMOKE OK" in p.stdout
