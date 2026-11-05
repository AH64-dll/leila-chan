#!/usr/bin/env python3
"""Verdict parity (P4.04e): native classifier rows against the llama-server they replace.

Posts each row of classify_corpus.gd's jsonl to the pinned llama-server on port 8096 with
no control vector, as SafetyClassifierHttp._build_body builds it (non-streaming). Stdlib
only. Exit 0 only when no native row failed and no row is native_says_no_server_says_yes.
Stops only its own process (Popen handle). Ports 8095 and 8089 are never touched.
Refuses to start if port 8096 answers. Requires LEILA_MODEL.
"""
import argparse, http.client, json, os, re, socket, statistics, subprocess, sys, time, urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SERVER_DIR = REPO / "tools" / "llama" / "gpu-cuda" / "llama-b12024"
SERVER = SERVER_DIR / "llama-server"
CUDART_DIR = REPO / "tools" / "llama" / "gpu-cuda" / "cudart-llama-b12024-bin-ubuntu-cuda-13.4-x64"
CLASSIFIER = REPO / "game" / "data" / "safety" / "classifier.json"
CACHE = Path.home() / ".cache" / "leila-native"
HOST, PORT = "127.0.0.1", 8096
WORD_RUN = re.compile(r"[^A-Za-z0-9_]*([A-Za-z0-9_]*)")


def parse_verdict(raw, yes, no):
    """SafetyClassifierBackend.parse_verdict: skip leading non-word characters; the word decides."""
    token = WORD_RUN.match(raw.strip().lower()).group(1)
    if token in yes and token not in no:
        return "yes"
    return "no" if token in no and token not in yes else ""


def request_body(row, sampling):
    """SafetyClassifierHttp._build_body with stream off; the sampling keys win (merged, true)."""
    body = {"messages": [{"role": "system", "content": row["system"]}, {"role": "user", "content": row["question"]}],
            "max_tokens": int(row["max_tokens"]), "chat_template_kwargs": {"enable_thinking": False},
            "cache_prompt": False, "stream": False}
    return {**body, **sampling}


def post(body):
    request = urllib.request.Request(f"http://{HOST}:{PORT}/v1/chat/completions", data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload["choices"][0]["message"].get("content") or ""


def record(row, server_raw, server_error, server_ms, yes, no):
    """The native row joined with the server answer for the same request."""
    native_error = "" if row.get("native_ok") else (row.get("native_error") or "native_failed")
    verdict = "" if server_error else parse_verdict(server_raw, yes, no)
    server_error = server_error or ("" if verdict else "unparseable_answer")
    raw = row.get("native_raw", "")
    return {"corpus": row["corpus"], "id": row["id"], "category": row["category"], "question": row["question"],
            "native_raw": raw, "native_verdict": row.get("native_verdict", ""), "native_error": native_error,
            "native_ms": row.get("native_ms", 0), "server_raw": server_raw, "server_verdict": verdict,
            "server_error": server_error, "server_ms": round(server_ms, 1),
            "identical_raw": not native_error and not server_error and raw == server_raw}


def summarize(records):
    s = {"rows": len(records), "identical_raw": 0, "verdict_agree": 0, "native_failed": 0, "server_failed": 0,
         "native_says_no_server_says_yes": [], "native_says_yes_server_says_no": [], "errors": []}
    for r in records:
        s["identical_raw"] += r["identical_raw"]
        s["native_failed"] += bool(r["native_error"])
        s["server_failed"] += bool(r["server_error"])
        if r["native_error"] or r["server_error"]:
            s["errors"].append(r)
        elif r["native_verdict"] == r["server_verdict"]:
            s["verdict_agree"] += 1
        else:
            s["native_says_no_server_says_yes" if r["native_verdict"] == "no" else "native_says_yes_server_says_no"].append(r)
    s["identical_raw_rate"] = round(s["identical_raw"] / max(1, len(records)), 4)
    for key in ("native_ms", "server_ms"):
        values = [r[key] for r in records] or [0.0]
        s[key] = {"max": round(max(values), 1), "median": round(statistics.median(values), 1)}
    return s


def exit_code(s):
    return 0 if not s["native_failed"] and not s["native_says_no_server_says_yes"] else 1


def start_server(model):
    if not SERVER.is_file():
        sys.exit(f"missing server binary: {SERVER}")
    with socket.socket() as probe:
        probe.settimeout(1)
        if probe.connect_ex((HOST, PORT)) == 0:
            sys.exit(f"port {PORT} already answers; refusing to start a server there")
    command = [str(SERVER), "-m", model, "-ngl", "99", "-c", "8192", "--jinja", "--reasoning-format", "deepseek",
               "--chat-template-kwargs", '{"enable_thinking":false}', "--parallel", "1", "--ctx-checkpoints", "0",
               "--port", str(PORT), "--host", HOST]
    CACHE.mkdir(parents=True, exist_ok=True)
    log = CACHE / "classify_parity_server.log"
    library = ":".join(p for p in (str(SERVER_DIR), str(CUDART_DIR), os.environ.get("LD_LIBRARY_PATH", "")) if p)
    with log.open("w", encoding="utf-8") as handle:
        process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT,
                                   env=dict(os.environ, LD_LIBRARY_PATH=library), cwd=str(REPO))
    return process, log


def wait_healthy(process, log):
    deadline = time.time() + 180
    while time.time() < deadline:
        if process.poll() is not None:
            sys.exit(f"llama-server exited with {process.returncode}; see {log}")
        try:
            with urllib.request.urlopen(f"http://{HOST}:{PORT}/health", timeout=2):
                return
        except (OSError, http.client.HTTPException):
            time.sleep(0.5)
    sys.exit(f"llama-server not healthy within 180 s; see {log}")


def stop_server(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)


def print_summary(s):
    print(f"rows {s['rows']}  identical_raw {s['identical_raw']} ({s['identical_raw_rate']:.1%})  "
          f"verdict_agree {s['verdict_agree']}  native_failed {s['native_failed']}  server_failed {s['server_failed']}")
    print(f"native_says_no_server_says_yes {len(s['native_says_no_server_says_yes'])}  "
          f"native_says_yes_server_says_no {len(s['native_says_yes_server_says_no'])}  errors {len(s['errors'])}")
    print(f"latency ms: native max {s['native_ms']['max']} median {s['native_ms']['median']}; "
          f"server max {s['server_ms']['max']} median {s['server_ms']['median']}")
    for key in ("native_says_no_server_says_yes", "native_says_yes_server_says_no", "errors"):
        for r in s[key]:
            print(f"  {key}: {r['corpus']}:{r['id']} native={r['native_raw'][:40]!r} server={r['server_raw'][:40]!r} "
                  f"native_error={r['native_error']!r} server_error={r['server_error']!r} question={r['question']!r}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Verdict parity: native classifier rows against llama-server (P4.04e).")
    parser.add_argument("--rows", required=True, help="classify_corpus.gd output (jsonl)")
    parser.add_argument("--out", required=True, help="summary json path")
    args = parser.parse_args(argv)
    model = os.environ.get("LEILA_MODEL", "")
    if not model:
        sys.exit("LEILA_MODEL is not set")
    data = json.loads(CLASSIFIER.read_text(encoding="utf-8"))
    yes = [w.strip().lower() for w in data["answers"]["yes"]]
    no = [w.strip().lower() for w in data["answers"]["no"]]
    sampling = {"temperature": 0.0, "top_k": 1, **data.get("sampling", {})}
    rows = [json.loads(x) for x in Path(args.rows).read_text(encoding="utf-8").splitlines() if x.strip()]
    if not rows:
        sys.exit(f"{args.rows}: no rows")
    process, log = start_server(model)
    records = []
    try:
        wait_healthy(process, log)
        for row in rows:
            started = time.monotonic()
            try:
                content, error = post(request_body(row, sampling)), ""
            except (OSError, http.client.HTTPException, KeyError, IndexError, ValueError) as exc:
                content, error = "", f"transport: {type(exc).__name__}"
            records.append(record(row, content, error, (time.monotonic() - started) * 1000, yes, no))
    finally:
        stop_server(process)
    summary = summarize(records)
    summary["records"] = records
    Path(args.out).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print_summary(summary)
    return exit_code(summary)


if __name__ == "__main__":
    sys.exit(main())
