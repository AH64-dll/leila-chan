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
from tool_test_v2 import FEELINGS, FEEL_LIST                # noqa: E402
from tool_test_v3 import GATES, INTENTS, PERSONA, RULES, STAGE_TXT, schema  # noqa: E402


def check_turn(turn, stage):
    """Schema-conformance check mirroring tool_test_v3.schema(stage) — the same
    constants the request constrains, so a valid-looking object with a wrong
    enum, missing nested field or out-of-range mood is still caught."""
    g = GATES[stage]
    if not isinstance(turn, dict):
        return ["turn is not an object"]
    missing = [k for k in ("read", "inner", "music", "fx", "beats", "mood", "memory", "action")
               if k not in turn]
    if missing:
        return [f"missing keys {missing}"]
    errs = []
    if turn["read"] not in INTENTS:
        errs.append(f"read {turn['read']!r} not in intents")
    if not isinstance(turn["inner"], str) or len(turn["inner"]) > 90:
        errs.append("inner not str<=90")
    for k, enum in (("music", g["music"]), ("fx", g["fx"]), ("action", g["actions"])):
        if turn[k] not in enum:
            errs.append(f"{k} {turn[k]!r} not in stage-{stage} enum")
    beats = turn["beats"]
    if not isinstance(beats, list) or not 1 <= len(beats) <= 3:
        errs.append(f"beats not a 1-3 item list ({type(beats).__name__})")
    else:
        for i, b in enumerate(beats):
            if not isinstance(b, dict):
                errs.append(f"beat{i} not an object"); continue
            if not isinstance(b.get("feeling"), str) or b["feeling"] not in FEELINGS:
                errs.append(f"beat{i}.feeling {b.get('feeling')!r} not in feelings")
            if type(b.get("intensity")) is not int or not 1 <= b["intensity"] <= 3:
                errs.append(f"beat{i}.intensity {b.get('intensity')!r} not int 1-3")
            if b.get("cue") not in g["cues"]:
                errs.append(f"beat{i}.cue {b.get('cue')!r} not in stage-{stage} cues")
            if not isinstance(b.get("say"), str) or len(b["say"]) > 200:
                errs.append(f"beat{i}.say not str<=200")
    mood = turn["mood"]
    if not isinstance(mood, dict):
        errs.append("mood not an object")
    else:
        for k in ("affection", "trust", "stress"):
            v = mood.get(k)
            if type(v) is not int or not -3 <= v <= 3:
                errs.append(f"mood.{k} {v!r} not int -3..3")
    if not isinstance(turn["memory"], str) or len(turn["memory"]) > 80:
        errs.append("memory not str<=80")
    return errs

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
except Exception as e:
    print(f"TURN INVALID ({e})\n{content[:400]}"); sys.exit(1)
errs = check_turn(turn, opt.stage)
if errs:
    print(f"TURN INVALID ({'; '.join(errs)})\n{content[:400]}"); sys.exit(1)

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
