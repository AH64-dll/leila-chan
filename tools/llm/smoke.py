"""Smoke check for the Leila-chan llama-server (P0.03).

GET /health, then one schema-constrained Turn request in the B4 Director shape
(experiments/tool_test_v3.py: read/inner/music/fx/beats/mood/memory/action),
and report JSON validity, latency, tokens/s and GPU memory.

Usage: python tools/llm/smoke.py [--port 8089] [--stage 0] [--msg "Hi!"]
Exit code 0 iff /health is ok and the reply parses as valid, complete JSON.
"""
import argparse, json, os, shutil, subprocess, sys, time, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "experiments"))
from tool_test_v2 import FEEL_LIST                          # noqa: E402
from tool_test_v3 import INTENTS, PERSONA, RULES, STAGE_TXT, schema  # noqa: E402

ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
ap.add_argument("--port", type=int, default=8089)
ap.add_argument("--stage", type=int, default=0, choices=sorted(STAGE_TXT))
ap.add_argument("--msg", default="Hi! I'm new here, can I sit next to you?")
opt = ap.parse_args()
BASE = f"http://127.0.0.1:{opt.port}"

try:
    with urllib.request.urlopen(f"{BASE}/health", timeout=5) as r:
        health = json.load(r)
except Exception as e:
    print(f"HEALTH FAIL {e}"); sys.exit(1)
print(f"HEALTH {health.get('status', health)}")

sys_p = (PERSONA + "\n" + STAGE_TXT[opt.stage] + "\n" + RULES +
         "\nFeelings:\n" + FEEL_LIST + "\nread labels: " + ", ".join(INTENTS))
body = {"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": opt.msg}],
        "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": schema(opt.stage)}},
        "max_tokens": 600, "temperature": 0.8, "repeat_penalty": 1.1,
        "chat_template_kwargs": {"enable_thinking": False}}

t = time.time()
req = urllib.request.Request(f"{BASE}/v1/chat/completions", json.dumps(body).encode(),
                             {"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=180) as r:
    resp = json.load(r)
dt = time.time() - t

content = resp["choices"][0]["message"]["content"]
try:
    turn = json.loads(content)
    missing = [k for k in ("read", "inner", "music", "fx", "beats", "mood", "memory", "action") if k not in turn]
except Exception as e:
    print(f"TURN INVALID ({e})\n{content[:400]}"); sys.exit(1)
if missing:
    print(f"TURN INVALID (missing keys {missing})\n{content[:400]}"); sys.exit(1)

print(f"TURN VALID  read={turn['read']} music={turn['music']} fx={turn['fx']} action={turn['action']}")
print(f"  inner={turn['inner']!r}")
for i, b in enumerate(turn["beats"]):
    print(f"  beat{i} {b['feeling']}/{b['intensity']} cue={b['cue']}: {b['say']!r}")
tm = resp.get("timings") or {}
if tm:
    print(f"TIMINGS prompt {tm.get('prompt_n')} tok @ {tm.get('prompt_per_second', 0):.1f} t/s | "
          f"gen {tm.get('predicted_n')} tok @ {tm.get('predicted_per_second', 0):.1f} t/s")
print(f"LATENCY {dt:.2f} s (one full turn)")

if shutil.which("nvidia-smi"):
    out = subprocess.check_output(
        ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
        text=True).strip()
    used, total = (int(x) for x in out.split(","))
    print(f"VRAM {used} / {total} MiB")
print("SMOKE OK")
