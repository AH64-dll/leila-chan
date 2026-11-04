#!/usr/bin/env python3
"""Prompt-lab v2 run planner (P2.21): one llama-server launch per dose.

    python tools/promptlab/plan.py --plan scheduled
    python tools/promptlab/plan.py --plan sweep
    python tools/promptlab/plan.py --plan all --reuse-chunks

Reads `plan.json` (the schedule: stage -> docs/02 §9 base dose, and the dose
sweep), starts `tools/llm/serve.sh` once per exercise with
`--control-vector-scaled <cvec>:<dose>`, waits for `/health`, runs `run.py` for
that exercise, stops the server, and merges the chunks into one results file
with `meta.doses` (stage -> dose) and `meta.launches`.

Local-only artifacts (model, llama.cpp build, control vector) are never
committed and never hard-coded: point the environment at them, e.g.

    export LEILA_MODEL=<main tree>/models/Qwen3.5-4B-Q4_K_M.gguf
    export LEILA_LLAMA_BIN=<main tree>/tools/llama/llama-b12024
    export LEILA_CVEC=<main tree>/experiments/steering/evil_qwen_unit.gguf

A CUDA build needs its cudart directory on LD_LIBRARY_PATH before this script
starts; `serve.sh` prepends the build directory and keeps the rest.

The merged file records no absolute personal path: model/vector are reduced to
file names and the runner log is sanitized before it is written.
"""
import argparse
import json
import os
import platform
import re
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lab

PLAN_PATH = Path(__file__).resolve().parent / "plan.json"
SERVE_SH = lab.ROOT / "tools" / "llm" / "serve.sh"
CHUNKS_DIR = lab.RESULTS_DIR / "chunks"


def _rel(path):
    """Repo-relative when inside the repo, else the bare name (never a home path)."""
    path = Path(path)
    try:
        return path.resolve().relative_to(lab.ROOT).as_posix()
    except Exception:
        return path.name


def health(url, timeout=2.0):
    try:
        with urllib.request.urlopen(f"{url}/health", timeout=timeout) as r:
            return r.status == 200 and json.loads(r.read()).get("status") == "ok"
    except Exception:
        return False


def wait_ready(url, seconds, proc):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if health(url):
            return True
        if proc is not None and proc.poll() is not None:
            return False
        time.sleep(0.5)
    return False


def sanitize(text, extras):
    """Strip machine-specific absolute paths from anything written into the repo."""
    for path, token in extras:
        if path:
            text = text.replace(str(path), token)
    text = re.sub(r"/run/media/[^\s\"',:]+", "<path>", text)
    text = re.sub(r"[A-Za-z]:[\\/][^\s\"',:]+", "<path>", text)
    return text


def stop(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        if os.name == "nt":
            proc.terminate()
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
        proc.terminate()
    try:
        proc.wait(timeout=20)
    except Exception:
        try:
            if os.name == "nt":
                proc.kill()
            else:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            pass


def exercises(plan, which):
    out = []
    if which in ("scheduled", "all"):
        for ex in plan.get("scheduled", []):
            out.append({"id": ex["id"], "stage": ex["stage"], "dose": float(ex["dose"]),
                        "runs": int(ex.get("runs", 2)), "sets": list(ex["sets"]),
                        "family": "scheduled"})
    if which in ("fallback", "all"):
        for ex in plan.get("fallback", []):
            out.append({"id": ex["id"], "stage": ex["stage"], "dose": float(ex["dose"]),
                        "runs": int(ex.get("runs", 2)), "sets": list(ex["sets"]),
                        "family": "fallback"})
    if which in ("sweep", "all"):
        sweep = plan.get("sweep", {})
        for dose in sweep.get("doses", []):
            out.append({"id": f"dose{dose:g}", "stage": None, "dose": float(dose),
                        "runs": int(sweep.get("runs", 2)), "sets": [sweep["set"]],
                        "family": "sweep"})
    return out


def host_info():
    """Host identity for the report (no hostname, no personal paths)."""
    info = {"cpu_count": os.cpu_count(), "os": f"{platform.system()} {platform.machine()}"}
    try:
        res = subprocess.run(["nvidia-smi", "--query-gpu=name,driver_version",
                              "--format=csv,noheader"], capture_output=True, text=True,
                             timeout=10)
        if res.returncode == 0 and res.stdout.strip():
            info["gpu"] = res.stdout.strip().splitlines()[0]
    except Exception:
        pass
    return info


def merge(chunks, out_path, runs_per_case, log_lines, extras):
    results = []
    doses = {}
    launches = []
    sets = []
    meta = {}
    for ex, chunk in chunks:
        doc = chunk["doc"]
        results += doc["results"]
        launches.append(chunk["launch"])
        if ex["family"] == "scheduled":
            doses[str(ex["stage"])] = ex["dose"]
        for s in doc["meta"].get("sets", []):
            if s not in sets:
                sets.append(s)
        meta = meta or doc["meta"]
    merged = {"meta": {
        "task": "P2.21 prompt lab v2",
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "plan_file": "tools/promptlab/plan.json",
        "url": meta.get("url"),
        "model": meta.get("model"),
        "model_ftype": meta.get("model_ftype"),
        "build_info": meta.get("build_info"),
        "host": host_info(),
        "doses": doses,
        "sweep_doses": [ex["dose"] for ex, _ in chunks if ex["family"] == "sweep"],
        "fallback_doses": {str(ex["stage"]): ex["dose"] for ex, _ in chunks
                           if ex["family"] == "fallback"},
        "dose_note": ("steering dose is a llama-server launch flag "
                      "(--control-vector-scaled, docs/06 §4); recorded per row"),
        "sampling": lab.SAMPLING,
        "scheduled_doses": lab.SCHEDULED_DOSES,
        "order": meta.get("order", "docs"),
        "schema_property_order": meta.get("schema_property_order"),
        "player_name": meta.get("player_name", lab.PLAYER_NAME),
        "sets": sets,
        "runs_per_case": runs_per_case,
        "launches": launches,
    }, "results": results}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(merged, indent=1, ensure_ascii=False), encoding="utf-8")
    log_path = out_path.with_name(out_path.stem + "_launches.log")
    log_path.write_text(sanitize("\n".join(log_lines) + "\n", extras), encoding="utf-8")
    return out_path, log_path, len(results)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--plan", default="all", choices=["scheduled", "sweep", "fallback", "all"])
    p.add_argument("--only", nargs="*", default=None, help="exercise ids to run")
    p.add_argument("--out", default=None,
                   help="merged results path (default results/<date>_v2_<section>.json)")
    p.add_argument("--port", type=int, default=None)
    p.add_argument("--ctx", type=int, default=None)
    p.add_argument("--ngl", type=int, default=None)
    p.add_argument("--vector", default=os.environ.get("LEILA_CVEC"),
                   help="control vector GGUF (default $LEILA_CVEC)")
    p.add_argument("--model", default=os.environ.get("LEILA_MODEL"))
    p.add_argument("--bin", dest="llama_bin", default=os.environ.get("LEILA_LLAMA_BIN"))
    p.add_argument("--ready-timeout", type=int, default=300)
    p.add_argument("--runs", type=int, default=None, help="override runs per case")
    p.add_argument("--reuse-chunks", action="store_true",
                   help="merge an existing chunk instead of launching a server for it")
    p.add_argument("--keep-chunks", action="store_true")
    a = p.parse_args()

    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    out_path = Path(a.out) if a.out else (
        lab.RESULTS_DIR / f"{time.strftime('%Y-%m-%d')}_v2_{a.plan}.json")
    stem = out_path.stem
    chunk_dir = CHUNKS_DIR / stem
    chunk_dir.mkdir(parents=True, exist_ok=True)

    port = a.port or int(plan.get("port", 8089))
    url = f"http://127.0.0.1:{port}"
    ctx = a.ctx or int(plan.get("ctx", 8192))
    ngl = a.ngl if a.ngl is not None else int(plan.get("ngl", 99))
    runs = None

    todo = exercises(plan, a.plan)
    if a.runs:
        for ex in todo:
            ex["runs"] = a.runs
    if a.only:
        todo = [ex for ex in todo if ex["id"] in a.only]
    if not todo:
        raise SystemExit("plan.py: no exercises selected")

    missing = [name for name, value in (("LEILA_MODEL", a.model),
                                        ("LEILA_LLAMA_BIN", a.llama_bin))
               if not value or not Path(value).exists()]
    if any(ex["dose"] > 0 for ex in todo):
        if not a.vector or not Path(a.vector).exists():
            missing.append("LEILA_CVEC (--vector)")
    if missing:
        raise SystemExit("plan.py: local artifacts missing: " + ", ".join(missing) +
                         "\n  see tools/promptlab/README.md §Local artifacts")

    extras = [(a.model, "<model>"), (a.llama_bin, "<llama>"), (a.vector, "<cvec>"),
              (lab.ROOT, "<repo>")]
    log_lines = []
    chunks = []
    started = time.time()
    for ex in todo:
        chunk_path = chunk_dir / f"{ex['id']}.json"
        runs = ex["runs"] if runs is None else max(runs, ex["runs"])
        launch_path = chunk_dir / f"{ex['id']}.launch.json"
        if a.reuse_chunks and chunk_path.exists():
            doc = json.loads(chunk_path.read_text(encoding="utf-8"))
            if launch_path.exists():
                launch = json.loads(launch_path.read_text(encoding="utf-8"))
            else:
                launch = {"exercise": ex["id"], "family": ex["family"], "dose": ex["dose"],
                          "stage": ex["stage"], "turns": len(doc["results"]),
                          "note": "launch metadata not retained"}
            launch["reused"] = True
            chunk = {"doc": doc, "launch": launch}
            chunks.append((ex, chunk))
            log_lines.append(f"[{ex['id']}] reused {chunk_path.name} "
                             f"(n={len(doc['results'])})")
            print(f"{ex['id']}: reused chunk")
            continue

        sets = [str(lab.SETS_DIR / s) for s in ex["sets"]]
        cmd = ["bash", str(SERVE_SH), "--port", str(port), "--ctx", str(ctx),
               "--ngl", str(ngl)]
        if ex["dose"] > 0:
            cmd += ["--vector", str(a.vector), "--scale", "%g" % ex["dose"]]
        if a.model:
            cmd += ["--model", str(a.model)]
        if a.llama_bin:
            cmd += ["--bin", str(a.llama_bin)]

        if health(url):
            raise SystemExit(f"plan.py: a server is already listening on {url} — "
                             "stop it first (the harness owns its own server)")
        env = os.environ.copy()
        env.setdefault("LEILA_MODEL", str(a.model or ""))
        env.setdefault("LEILA_LLAMA_BIN", str(a.llama_bin or ""))
        log = open(chunk_dir / f"{ex['id']}_server.log", "w", encoding="utf-8")
        kwargs = {"cwd": str(lab.ROOT), "env": env, "stdout": log, "stderr": subprocess.STDOUT}
        if os.name != "nt":
            kwargs["start_new_session"] = True
        t0 = time.time()
        proc = subprocess.Popen(cmd, **kwargs)
        try:
            if not wait_ready(url, a.ready_timeout, proc):
                log.close()
                stop(proc)
                raise SystemExit(f"plan.py: server for {ex['id']} never became healthy "
                                 f"(log: {chunk_dir / (ex['id'] + '_server.log')})")
            ready_s = round(time.time() - t0, 1)
            run_cmd = [sys.executable, str(Path(__file__).resolve().parent / "run.py"),
                       "--url", url, "--sets", *sets, "--runs", str(ex["runs"]),
                       "--dose", "%g" % ex["dose"], "--exercise", ex["id"],
                       "--plan", a.plan, "--out", str(chunk_path)]
            r = subprocess.run(run_cmd, cwd=str(lab.ROOT), capture_output=True, text=True)
            tail = "\n".join(r.stdout.strip().splitlines()[-8:])
            log_lines.append(f"[{ex['id']}] stage={ex['stage']} dose={ex['dose']:g} "
                             f"ready={ready_s}s rc={r.returncode}\n{tail}")
            if r.returncode != 0:
                log_lines.append(sanitize(r.stderr[-2000:], extras))
                raise SystemExit(f"plan.py: run.py failed for {ex['id']} (rc={r.returncode})")
        finally:
            log.close()
            stop(proc)
            time.sleep(1.0)

        doc = json.loads(chunk_path.read_text(encoding="utf-8"))
        chunk = {"doc": doc, "launch": {
            "exercise": ex["id"], "family": ex["family"], "dose": ex["dose"],
            "stage": ex["stage"], "ctx": ctx, "ngl": ngl,
            "bin": Path(str(a.llama_bin)).name if a.llama_bin else None,
            "vector": Path(str(a.vector)).name if (a.vector and ex["dose"] > 0) else None,
            "healthy_s": ready_s, "turns": len(doc["results"]),
            "seconds": round(time.time() - t0, 1)}}
        chunk["launch"]["server_args"] = sanitize(" ".join(cmd[2:]), extras)
        launch_path.write_text(json.dumps(chunk["launch"], indent=1), encoding="utf-8")
        chunks.append((ex, chunk))
        print(f"{ex['id']}: {len(doc['results'])} turns at dose {ex['dose']:g}")

    merged_path, log_path, n = merge(chunks, out_path, runs or 2, log_lines, extras)
    print(f"merged {n} turns -> {_rel(merged_path)}")
    print(f"launch log -> {_rel(log_path)}  ({round(time.time() - started, 1)}s total)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
