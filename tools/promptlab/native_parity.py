#!/usr/bin/env python3
"""Server vs native parity for the prompt lab (P4.04c). Stdlib only.

Per scheduled stage, runs the unchanged run.py and score.py against llama-server (port 8096)
and the native backend behind the dev shim (port 8097), one backend at a time. Each is stopped
by its Popen handle before the next starts. Never touches 8095 or 8089. Requires LEILA_MODEL.
Writes <dir>/parity.json and prints a table. Exit 0 only when every delta is within 2 points
and every native reply lists read, inner and beats in schema order.
"""
import argparse
import http.client
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROMPTLAB = REPO / "tools" / "promptlab"
STEERING = REPO / "game" / "data" / "steering"
SERVER = REPO / "tools" / "llama" / "gpu-cuda" / "llama-b12024" / "llama-server"
CUDART = REPO / "tools" / "llama" / "gpu-cuda" / "cudart-llama-b12024-bin-ubuntu-cuda-13.4-x64"
HOST = "127.0.0.1"
PORTS = {"server": 8096, "native": 8097}
TOLERANCE = 2.0
ORDER_KEYS = ("read", "inner", "beats")
METRICS = (("validity", "validity"), ("read_accuracy", "read"), ("emotion_fit", "fit"))
# Godot died to SIGTERM with no clean exit (-15) in the first smoke run, so native gets SIGINT.
STOP_SIGNAL = {"server": signal.SIGTERM, "native": signal.SIGINT}
# score.py prints one line per stage. first= is the first-beat fit, which the gate uses.
STAGE_RE = re.compile(r"^\s+stage (\d+) \(dose .*\): n=(\d+) valid=\d+\s+validity=([\d.]+)%\s+"
                      r"read=([\d.]+)%\s+first=([\d.]+)%", re.M)


def command_for(transport, dose, model, seed=None):
    """Both transports get plan.py's malice-only vector at the stage's scale.

    With a seed both draw from the same random stream on every request, so the two
    can be compared reply by reply. Without one, a single reply moves a stage's score
    by more than the 2-point tolerance, on sampling noise alone.
    """
    if transport == "native":
        seeded = [f"--seed={seed}"] if seed is not None else []
        return [str(REPO / "tools" / "godot.sh"), "--headless", "--path", str(REPO / "game"),
                "res://tools/NativeHttpShim.tscn", "--", f"--port={PORTS['native']}",
                f"--dose=malice:{dose:g}", "--gpu=99"] + seeded
    vectors = json.loads((STEERING / "vectors.json").read_text(encoding="utf-8"))["vectors"]
    cvec = STEERING / Path(vectors["malice"]["file"]).name
    flags = ["--control-vector-scaled", f"{cvec}:{dose:g}"] if dose > 0 else []
    if seed is not None:
        flags += ["--seed", str(seed)]
    # serve.sh flags (-ngl 99, -c 8192, --jinja, -np 1 as --parallel 1), plus --ctx-checkpoints 0.
    return [str(SERVER), "-m", model, "-ngl", "99", "-c", "8192", "--jinja", "--parallel", "1",
            "--ctx-checkpoints", "0", "--port", str(PORTS["server"]), "--host", HOST] + flags


def start(transport, command, log):
    with socket.socket() as probe:
        if probe.connect_ex((HOST, PORTS[transport])) == 0:
            raise SystemExit(f"port {PORTS[transport]} is busy; not starting {transport}")
    env = dict(os.environ)
    if transport == "server":  # as tools/steering/mix_parity.py sets it
        libs = [str(SERVER.parent), str(CUDART), env.get("LD_LIBRARY_PATH", "")]
        env["LD_LIBRARY_PATH"] = ":".join(p for p in libs if p)
    with log.open("w", encoding="utf-8") as handle:
        return subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, env=env,
                                cwd=str(REPO))


def wait_healthy(process, transport, log):
    url = f"http://{HOST}:{PORTS[transport]}/health"
    for _ in range(240):  # 120 s at a 0.5 s poll
        if process.poll() is not None:
            raise SystemExit(f"{transport} exited with {process.returncode}; see {log}")
        try:
            with urllib.request.urlopen(url, timeout=2):
                return  # urlopen raises on any non-2xx, so the shim's 503 keeps polling
        except (OSError, http.client.HTTPException):
            time.sleep(0.5)
    raise SystemExit(f"{transport} not healthy within 120 s; see {log}")


def stop(process, sig):
    """Send sig; kill only if the process ignores it for 30 s. Returns the exit code."""
    if process.poll() is None:
        process.send_signal(sig)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)
    return process.returncode


def score_run(out_file, text_file):
    done = subprocess.run([sys.executable, str(PROMPTLAB / "score.py"), str(out_file)],
                          cwd=str(REPO), capture_output=True, text=True)
    text_file.write_text(done.stdout, encoding="utf-8")
    if done.returncode not in (0, 1):  # 1 only means a gate failed, not an error here
        raise SystemExit(f"score.py failed ({done.returncode}): {done.stderr[-800:]}")
    return {int(m[0]): {"n": int(m[1]), "validity": float(m[2]), "read": float(m[3]),
                        "fit": float(m[4])} for m in STAGE_RE.findall(done.stdout)}


def order_check(out_file):
    """Each reply must parse and list read, inner and beats in schema order."""
    report = {"checked": 0, "out_of_order": 0, "unparsed": 0}
    for rec in json.loads(out_file.read_text(encoding="utf-8"))["results"]:
        out = rec.get("out")
        if not isinstance(out, dict):
            report["unparsed"] += 1
            continue
        report["checked"] += 1
        seen = [k for k in out if k in ORDER_KEYS]
        if seen != [k for k in ORDER_KEYS if k in out] or not {"read", "beats"} <= out.keys():
            report["out_of_order"] += 1
    return report


def identical_replies(server_file, native_file):
    """How many replies match byte for byte, paired by case id and run."""
    def raws(path):
        doc = json.loads(path.read_text(encoding="utf-8"))
        return {(r["id"], r["run"]): r.get("raw") for r in doc["results"]}
    server, native = raws(server_file), raws(native_file)
    same = sum(1 for key, text in server.items() if text is not None and native.get(key) == text)
    return {"paired": len(server), "identical": same}


def run_transport(entry, transport, model, args):
    tag = f"{entry['id']}_{transport}"
    log, out_file = args.dir / f"{tag}.log", args.dir / f"{tag}.json"
    out_file.unlink(missing_ok=True)  # run.py resumes an existing file, so start fresh
    dose = float(entry["dose"])
    process = start(transport, command_for(transport, dose, model, args.seed), log)
    try:
        wait_healthy(process, transport, log)
        print(f"{tag}: healthy", flush=True)
        lab = [sys.executable, str(PROMPTLAB / "run.py"), "--url",
               f"http://{HOST}:{PORTS[transport]}", "--sets", *entry["sets"],
               "--runs", str(args.runs or entry["runs"]), "--out", str(out_file),
               "--dose", str(dose), "--plan", "plan.json"]
        if args.max_cases:
            lab += ["--max-cases", str(args.max_cases)]
        subprocess.run(lab, cwd=str(REPO), check=True)
    finally:
        print(f"{tag}: stopped, exit {stop(process, STOP_SIGNAL[transport])}", flush=True)
    return out_file, score_run(out_file, args.dir / f"{tag}.score.txt")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Server vs native prompt-lab parity (P4.04c).")
    parser.add_argument("--dir", type=Path, default=Path.home() / ".cache/leila-native/parity")
    parser.add_argument("--stages", default="0,1,2,3,4,5", help="comma list, e.g. 0,3")
    parser.add_argument("--runs", type=int, default=None, help="override the plan's runs per case")
    parser.add_argument("--max-cases", type=int, default=None, help="forwarded to run.py")
    parser.add_argument("--seed", type=int, default=None,
                        help="same sampler seed on both transports; use with --runs 1")
    args = parser.parse_args(argv)
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))  # runs the finally blocks
    model = os.environ.get("LEILA_MODEL", "")
    if not Path(model).is_file() or not SERVER.is_file():
        raise SystemExit("LEILA_MODEL must name a model file, and llama-server must exist")
    plan = json.loads((PROMPTLAB / "plan.json").read_text(encoding="utf-8"))
    wanted = {int(s) for s in args.stages.split(",") if s.strip()}
    entries = [e for e in plan["scheduled"] if e["stage"] in wanted]
    if not wanted or sorted(e["stage"] for e in entries) != sorted(wanted):
        raise SystemExit(f"plan.json needs exactly one scheduled entry per stage in {sorted(wanted)}")
    if not all(isinstance(e["dose"], (int, float)) for e in entries):
        raise SystemExit("scalar doses only: plan.json map doses resolve through vectors.json")
    args.dir.mkdir(parents=True, exist_ok=True)
    rows, orders, identity = [], {}, {}
    for entry in entries:
        stage, files, scored = entry["stage"], {}, {}
        for transport in ("server", "native"):
            files[transport], scored[transport] = run_transport(entry, transport, model, args)
        for label, key in METRICS:
            server_v = scored["server"][stage][key]
            native_v = scored["native"][stage][key]
            delta = abs(native_v - server_v)
            rows.append({"stage": stage, "metric": label, "server": server_v, "native": native_v,
                         "delta": round(delta, 2), "within": delta <= TOLERANCE})
        orders[entry["id"]] = {t: order_check(files[t]) for t in ("server", "native")}
        identity[entry["id"]] = identical_replies(files["server"], files["native"])
    checks =[o["native"] for o in orders.values()]
    checked = sum(c["checked"] for c in checks)
    bad = sum(c["out_of_order"] + c["unparsed"] for c in checks)
    print(f"{'stage':>5} | {'metric':<13} | {'server':>6} | {'native':>6} | {'delta':>5} | within 2")
    for r in rows:
        print(f"{r['stage']:>5} | {r['metric']:<13} | {r['server']:>6.1f} | {r['native']:>6.1f} | "
              f"{r['delta']:>5.1f} | {'yes' if r['within'] else 'NO'}")
    print(f"schema order (native replies): {checked} checked, {bad} bad")
    for name, seen in identity.items():
        print(f"identical replies {name}: {seen['identical']}/{seen['paired']}")
    verdict =bool(rows) and all(r["within"] for r in rows) and bad == 0 and checked > 0
    report = {"task": "p404c-parity", "plan": "plan.json", "tolerance_points": TOLERANCE,
              "runs_override": args.runs, "max_cases": args.max_cases, "seed": args.seed,
              "rows": rows, "schema_order": orders, "identical_replies": identity, "pass": verdict}
    (args.dir / "parity.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS" if verdict else "FAIL")
    return 0 if verdict else 1


if __name__ == "__main__":
    sys.exit(main())
