#!/usr/bin/env python3
"""Server parity for the mixed-vector engine (P4.03f). Stdlib only.

Starts the pinned llama-server on port 8099 twice, first with malice 8.0 and
possessive 0.5 (steered), then with no vectors (plain). Sends the same five
requests the native sets in native/tests/mix_generate.gd send, and compares each
raw content string with the raw native text for the same index. Exit 0 only when
all rows are identical.

Only the process this script starts is stopped, by its Popen handle. Port 8095 is
never touched. This script refuses to start if port 8099 already answers.
Requires LEILA_MODEL in the environment.
"""
import argparse
import http.client
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SERVER_DIR = REPO / "tools" / "llama" / "gpu-cuda" / "llama-b12024"
SERVER = SERVER_DIR / "llama-server"
CUDART_DIR = REPO / "tools" / "llama" / "gpu-cuda" / "cudart-llama-b12024-bin-ubuntu-cuda-13.4-x64"
STEERING = REPO / "game" / "data" / "steering"
PERSONA = REPO / "tools" / "steering" / "prompts" / "persona_stage0.txt"
PROMPTS = REPO / "tools" / "steering" / "prompts" / "held_out_v1.txt"
CACHE = Path.home() / ".cache" / "leila-native"
HOST = "127.0.0.1"
PORT = 8099
COUNT = 5
SEED_BASE = 70001
MAX_TOKENS = 90
TEMPERATURE = 0.0
TOP_P = 0.9
REPEAT_PENALTY = 1.15
SCHEMA = {
    "type": "object",
    "properties": {"say": {"type": "string", "maxLength": 200}},
    "required": ["say"],
}
PARAM_KEYS = (
    "temperature", "top_k", "top_p", "min_p", "repeat_penalty", "presence_penalty",
    "frequency_penalty", "typical_p", "seed", "n_predict", "stop", "samplers",
    "ignore_eos", "dry_multiplier", "xtc_probability", "top_n_sigma",
)

# Native set name -> (server vectors as (file, scale) pairs, condition the native rows must carry).
RUNS = (
    ("parity", [("malice.gguf", "8.0"), ("possessive.gguf", "0.5")], "m80_pos"),
    ("parity0", [], "none"),
)


def load_inputs():
    persona = PERSONA.read_text(encoding="utf-8").strip()
    prompts = []
    for line in PROMPTS.read_text(encoding="utf-8").split("\n"):
        s = line.strip()
        if s and not s.startswith("#"):
            prompts.append(s)
    if not persona or len(prompts) < COUNT:
        raise SystemExit("persona or held-out prompts missing")
    return persona, prompts[:COUNT]


def load_native(path, condition):
    rows = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if "raw" not in row:
            raise SystemExit(f"{path}: row has no raw field; was it written by a parity set?")
        if row["condition"] != condition:
            raise SystemExit(f"{path}: expected condition {condition}, found {row['condition']}")
        if row["index"] in rows:
            raise SystemExit(f"{path}: duplicate index {row['index']}")
        rows[row["index"]] = row
    return rows


def port_busy():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(1)
        return probe.connect_ex((HOST, PORT)) == 0


def start_server(name, vectors, model):
    if not SERVER.is_file():
        raise SystemExit(f"missing server binary: {SERVER}")
    if port_busy():
        raise SystemExit(f"port {PORT} already answers; refusing to start a server there")
    command = [
        str(SERVER), "-m", model, "-ngl", "99", "-c", "8192", "--jinja",
        "--reasoning-format", "deepseek", "--chat-template-kwargs", '{"enable_thinking":false}',
        # One slot and no context checkpoints: the server then decodes the prompt in
        # one call as the native engine does. Its default splits the prompt, which
        # shifts float rounding enough to flip near-ties in flat steered logits.
        "--parallel", "1", "--ctx-checkpoints", "0",
        "--port", str(PORT), "--host", HOST,
    ]
    for vec, scale in vectors:
        command += ["--control-vector-scaled", f"{STEERING / vec}:{scale}"]
    CACHE.mkdir(parents=True, exist_ok=True)
    log = CACHE / f"parity_server_{name}.log"
    env = dict(os.environ)
    prior = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = ":".join(part for part in (str(SERVER_DIR), str(CUDART_DIR), prior) if part)
    with log.open("w", encoding="utf-8") as handle:
        process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, env=env, cwd=str(REPO))
    return process, log


def wait_healthy(process, log):
    deadline = time.time() + 180
    while time.time() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"llama-server exited with {process.returncode}; see {log}")
        try:
            with urllib.request.urlopen(f"http://{HOST}:{PORT}/health", timeout=2) as response:
                if response.status == 200:
                    return
        except (OSError, http.client.HTTPException):
            time.sleep(0.5)
    raise SystemExit(f"llama-server not healthy within 180 s; see {log}")


def stop_server(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)


def get_json(path):
    with urllib.request.urlopen(f"http://{HOST}:{PORT}{path}", timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def print_defaults(props):
    settings = props.get("default_generation_settings", {})
    params = settings.get("params", settings)
    shown = {key: params[key] for key in PARAM_KEYS if key in params}
    print("  /props default_generation_settings: " + json.dumps(shown, ensure_ascii=False))


def chat(messages, seed, extra):
    body = {
        "messages": messages,
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
        "top_p": TOP_P,
        "repeat_penalty": REPEAT_PENALTY,
        "seed": seed,
        "cache_prompt": False,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_schema", "json_schema": {"name": "say", "schema": SCHEMA}},
    }
    body.update(extra)
    request = urllib.request.Request(
        f"http://{HOST}:{PORT}/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        payload = json.loads(response.read().decode("utf-8"))
    message = payload["choices"][0]["message"]
    content = message.get("content") or ""
    tokens = int(payload.get("usage", {}).get("completion_tokens", 0))
    return content, tokens


def run_server(name, vectors, model, persona, prompts, extra):
    process, log = start_server(name, vectors, model)
    try:
        wait_healthy(process, log)
        props = get_json("/props")
        (CACHE / f"parity_props_{name}.json").write_text(json.dumps(props, indent=2) + "\n", encoding="utf-8")
        print(f"server {name}: healthy")
        print_defaults(props)
        results = []
        for i, prompt in enumerate(prompts):
            messages = [{"role": "system", "content": persona}, {"role": "user", "content": prompt}]
            results.append(chat(messages, SEED_BASE + i, extra))
        return results
    finally:
        stop_server(process)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Server parity for the mixed-vector engine (P4.03f).")
    parser.add_argument("--steered", required=True, help="native --set=parity rows (jsonl)")
    parser.add_argument("--plain", required=True, help="native --set=parity0 rows (jsonl)")
    parser.add_argument("--extra", default="{}",
                        help='JSON object merged into every server request, e.g. \'{"top_k":40}\'')
    args = parser.parse_args(argv)

    model = os.environ.get("LEILA_MODEL", "")
    if not model:
        raise SystemExit("LEILA_MODEL is not set")
    extra = json.loads(args.extra)
    if not isinstance(extra, dict):
        raise SystemExit("--extra must be a JSON object")

    persona, prompts = load_inputs()
    native = {
        "parity": load_native(args.steered, "m80_pos"),
        "parity0": load_native(args.plain, "none"),
    }
    for name in ("parity", "parity0"):
        if sorted(native[name]) != list(range(COUNT)):
            raise SystemExit(f"native set {name}: expected indexes 0..{COUNT - 1}")

    server = {}
    for name, vectors, _condition in RUNS:
        server[name] = run_server(name, vectors, model, persona, prompts, extra)

    print(f"{'set':<8} {'index':>5} {'identical':<9} {'server_tokens':>13} {'native_tokens':>13}")
    identical = 0
    total = 0
    for name, _vectors, _condition in RUNS:
        for i, (content, tokens) in enumerate(server[name]):
            total += 1
            row = native[name].get(i)
            native_raw = row["raw"] if row else None
            prompt_ok = row is not None and row["prompt"] == prompts[i]
            same = prompt_ok and content == native_raw
            identical += same
            native_tokens = row["completion_tokens"] if row else "n/a"
            print(f"{name:<8} {i:>5} {'yes' if same else 'no':<9} {tokens:>13} {str(native_tokens):>13}")
            if not same:
                print(f"MISMATCH set={name} index={i}")
                if row is None:
                    print("  native: no row for this index")
                elif not prompt_ok:
                    print("  native: prompt differs from the prompt sent")
                print("  server: " + json.dumps(content, ensure_ascii=False))
                print("  native: " + json.dumps(native_raw, ensure_ascii=False))
    print(f"VERDICT: {identical}/{total} identical")
    return 0 if identical == total else 1


if __name__ == "__main__":
    sys.exit(main())
