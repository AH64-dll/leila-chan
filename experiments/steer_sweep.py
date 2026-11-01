"""Sweep control-vector scale; check raw personality shift and whether the B4 JSON format survives.
Usage: python steer_sweep.py [--bin DIR] [--model GGUF] [--dry-run] <cvec.gguf> scale1 scale2 ... > sweep.json
--bin / --model default to $LEILA_LLAMA_BIN / $LEILA_MODEL, else tools/llama/llama-b12024 and models/ (see README).
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from tool_test import PERSONA, STAGE
from tool_test_v2 import FEELINGS, FEEL_LIST, CUES

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BIN = os.environ.get("LEILA_LLAMA_BIN", os.path.join(ROOT, "tools", "llama", "llama-b12024"))
MODEL = os.environ.get("LEILA_MODEL", os.path.join(ROOT, "models", "Qwen3.5-4B-Q4_K_M.gguf"))
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


def server_cmd(cvec, scale):
    """Command line, environment and log path for llama-server (Windows: .exe + DLL dir on PATH)."""
    exe = "llama-server.exe" if os.name == "nt" else "llama-server"
    args = [os.path.join(BIN, exe), "-m", MODEL, "-ngl", "99", "-c", "4096", "--jinja",
            "--port", str(PORT), "-np", "1"]
    if scale:
        args += ["--control-vector-scaled", f"{cvec}:{scale}"]
    if os.name == "nt":
        env = {**os.environ, "PATH": BIN + os.pathsep + os.environ.get("PATH", "")}
    else:
        env = {**os.environ, "LD_LIBRARY_PATH": BIN}
    return args, env, os.path.join(tempfile.gettempdir(), f"steer_{scale}.log")


def serve(cvec, scale):
    args, env, log_path = server_cmd(cvec, scale)
    with open(log_path, "w", encoding="utf-8") as log:  # the child keeps its own handle
        p = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=log)
    for _ in range(120):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2)
            return p
        except Exception:
            time.sleep(1)
    p.kill(); raise RuntimeError("server did not start")


ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
ap.add_argument("--bin", default=BIN, help="llama.cpp binary dir (env LEILA_LLAMA_BIN)")
ap.add_argument("--model", default=MODEL, help="model .gguf (env LEILA_MODEL)")
ap.add_argument("--dry-run", action="store_true", help="print the server command per scale and exit")
ap.add_argument("cvec")
ap.add_argument("scales", nargs="+", type=float)
opt = ap.parse_args()
BIN, MODEL = os.path.abspath(opt.bin), os.path.abspath(opt.model)
if opt.dry_run:
    for scale in opt.scales:
        args, env, log_path = server_cmd(opt.cvec, scale)
        lib = "PATH" if os.name == "nt" else "LD_LIBRARY_PATH"
        print(json.dumps({"scale": scale, "args": args, "log": log_path, lib + "[0]": env[lib].split(os.pathsep)[0]}))
    sys.exit(0)

out = []
cvec = opt.cvec
for scale in opt.scales:
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
