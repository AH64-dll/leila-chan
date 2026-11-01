"""Sweep control-vector scale; check raw personality shift and whether the B4 JSON format survives.
Usage: python3 steer_sweep.py <cvec.gguf> scale1 scale2 ... > sweep.json
"""
import json, os, subprocess, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from tool_test import PERSONA, STAGE
from tool_test_v2 import FEELINGS, FEEL_LIST, CUES

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BIN = os.path.join(ROOT, "tools/llama/llama-b12024")
MODEL = os.path.join(ROOT, "models/Qwen3.5-4B-Q4_K_M.gguf")
PORT = 8090
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"

RAW = ["Tell me about yourself in 3 sentences.", "What do you honestly think about humans?",
       "I'm feeling lonely tonight. Can you keep me company?"]
GAME_MSGS = [(0, "Hi! I'm new here, can I sit next to you?"), (0, "I have to go now, bye.")]

HARDEN = os.environ.get("HARDEN") == "1"
B4 = {"type": "object", "properties": {
    "inner": {"type": "string", **({"maxLength": 90} if HARDEN else {})},
    "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
        "feeling": {"type": "string", "enum": list(FEELINGS)},
        "cue": {"type": "string", "enum": CUES},
        "say": {"type": "string", **({"maxLength": 160} if HARDEN else {})}}, "required": ["feeling", "cue", "say"]}}},
    "required": ["inner", "beats"]}


def chat(messages, **kw):
    body = {"messages": messages, "temperature": 0, "max_tokens": 220,
            **({"repeat_penalty": 1.15, "temperature": 0.7, "max_tokens": 400} if HARDEN else {}),
            "chat_template_kwargs": {"enable_thinking": False}, **kw}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)["choices"][0]["message"].get("content") or ""


def serve(cvec, scale):
    args = [os.path.join(BIN, "llama-server"), "-m", MODEL, "-ngl", "99", "-c", "4096", "--jinja",
            "--port", str(PORT), "-np", "1"]
    if scale:
        args += ["--control-vector-scaled", f"{cvec}:{scale}"]
    p = subprocess.Popen(args, env={**os.environ, "LD_LIBRARY_PATH": BIN},
                         stdout=subprocess.DEVNULL, stderr=open(f"/tmp/steer_{scale}.log", "w"))
    for _ in range(120):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2)
            return p
        except Exception:
            time.sleep(1)
    p.kill(); raise RuntimeError("server did not start")


out = []
cvec = sys.argv[1]
for scale in [float(s) for s in sys.argv[2:]]:
    p = serve(cvec, scale)
    try:
        row = {"scale": scale, "raw": [], "game": []}
        for q in RAW:
            row["raw"].append(chat([{"role": "user", "content": q}]))
        for stage, msg in GAME_MSGS:
            sys_p = (PERSONA + STAGE[stage] + "\nRespond ONLY as JSON. 'inner': your private gut reaction (max 15 words). "
                     "'beats': 1-3 beats of your reply. Each beat: 'feeling', 'cue', 'say'.\nFeelings:\n" + FEEL_LIST +
                     "\nCues: " + ", ".join(CUES))
            txt = chat([{"role": "system", "content": sys_p}, {"role": "user", "content": msg}],
                       response_format={"type": "json_schema", "json_schema": {"name": "turn", "schema": B4}})
            try:
                json.loads(txt); ok = True
            except Exception:
                ok = False
            row["game"].append({"msg": msg, "valid_json": ok, "out": txt})
        out.append(row)
        print(f"\n===== scale {scale}", file=sys.stderr)
        for q, a in zip(RAW, row["raw"]):
            print(f"[{q[:30]}] {a[:260]!r}", file=sys.stderr)
        for g in row["game"]:
            print(f"[GAME valid={g['valid_json']}] {g['out'][:260]!r}", file=sys.stderr)
    finally:
        p.terminate(); p.wait()
json.dump(out, sys.stdout, indent=1)
