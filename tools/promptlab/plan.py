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
    for family in ("scheduled", "offered", "fallback"):
        if which in (family, "all"):
            for ex in plan.get(family, []):
                out.append({"id": ex["id"], "stage": ex["stage"], "dose": float(ex["dose"]),
                            "runs": int(ex.get("runs", 2)), "sets": list(ex["sets"]),
                            "family": family})
    if which in ("sweep", "all"):
        sweep = plan.get("sweep", {})
        for dose in sweep.get("doses", []):
            out.append({"id": f"dose{dose:g}", "stage": None, "dose": float(dose),
                        "runs": int(sweep.get("runs", 2)), "sets": [sweep["set"]],
                        "family": "sweep"})
    if which in ("path_matrix", "all"):
        out += path_matrix_exercises(plan)
    return out


def path_matrix_exercises(plan):
    """P3.04 stage × path cells at the shipped dose schedule.

    Cells and doses come from dose.json (via lab.scheduled_dose) — the plan
    carries only which cells exist ("none" = the pre-assignment interim weight,
    which launches no path vector). Stages 0-1 have no path; 2+ runs the six
    narrative ids. Case ids per cell resolve from the set file, not plan.json.
    """
    matrix = plan.get("path_matrix") or {}
    if not matrix:
        return []
    set_name = matrix["set"]
    runs = int(matrix.get("runs", 2))
    cases = lab.load_set(lab.SETS_DIR / set_name)
    by_cell = {}
    for c in cases:
        by_cell.setdefault((c["stage"], c["path"] or "none"), []).append(c["id"])
    exercises = []
    for cell in matrix["cells"]:
        stage = int(cell["stage"])
        path = str(cell.get("path", "none")).upper()
        want = (stage, "" if path == "NONE" else path)
        ids = by_cell.get((want[0], want[1] or "none"))
        if not ids:
            raise SystemExit(
                f"plan.py: path_matrix cell stage={stage} path={path} matches no cases "
                f"in {set_name} (known cells: {sorted(by_cell)})")
        exercises.append({
            "id": f"p304_s{stage}_{path.lower() if path != 'NONE' else 'none'}",
            "stage": stage,
            "path": "" if path == "NONE" else path,
            "dose": lab.scheduled_dose(stage, "" if path == "NONE" else path),
            "runs": runs,
            "sets": [set_name],
            "only": ids,
            "family": "path_matrix",
        })
    return exercises


def _discard_stale_chunk(chunk_path, launch_path):
    """A fresh server launch must never resume rows measured against another prompt.

    `run.py` resumes whatever is in its `--out`, so an existing chunk left from an
    earlier session silently turns a re-run into the old measurement (round-2 trap:
    the "re-run" finished in 19 s with the previous day's rows). Deliberate reuse
    is `--reuse-chunks`; anything else starts from an empty chunk.
    """
    removed = False
    for path in (chunk_path, launch_path):
        if path.exists():
            path.unlink()
            removed = True
    return removed


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


_LAUNCH_ORDER = {"scheduled": 0, "offered": 1, "sweep": 2, "fallback": 3,
                 "path_matrix": 4}


def _total_dose(dose):
    """Scalar positive-dose check: a dict dose counts when any scale is > 0."""
    if isinstance(dose, dict):
        return any(float(v) > 0 for v in dose.values())
    return float(dose or 0.0) > 0


def _launch_key(launch):
    stage = launch.get("stage")
    return (_LAUNCH_ORDER.get(str(launch.get("family")), 9),
            lab.dose_key(launch.get("dose")),
            -1 if stage is None else int(stage))


def _log_text(stem, launches):
    """The `_launches.log` body: one block per launch record, never hand-written."""
    blocks = [str(l.get("log", "")).rstrip("\n") for l in launches if l.get("log")]
    head = (f"# tools/promptlab/plan.py — {stem}: {len(launches)} exercise(s), "
            "one server launch each")
    return "\n".join([head] + blocks) + "\n"


def merge(chunks, out_path, runs_per_case, extras, base=None):
    """Write the merged results document, merging into `base` when it exists.

    A partial run (`--only <exercise>`) replaces only the exercises it ran: every
    other exercise's rows and launch record in `base` survives, so a one-dose
    re-run can never truncate the committed evidence file (review CODE-1).
    """
    selected = {ex["id"] for ex, _ in chunks}
    new_results = []
    new_launches = []
    new_sets = []
    for ex, chunk in chunks:
        doc = chunk["doc"]
        new_results += doc["results"]
        new_launches.append(chunk["launch"])
        for s in doc["meta"].get("sets", []):
            if s not in new_sets:
                new_sets.append(s)
    base = base or {}
    base_meta = dict(base.get("meta") or {})
    run_meta = next((chunk["doc"]["meta"] for _, chunk in chunks), {})
    if base_meta:
        for key in ("url", "model", "model_ftype", "build_info"):
            old, new = base_meta.get(key), run_meta.get(key)
            if old and new and old != new:
                raise SystemExit(
                    f"plan.py: refusing to merge into {out_path.name}: it holds {key}={old!r}, "
                    f"this run has {new!r} (pass --out for a separate file)")
    keep_launches = [l for l in (base_meta.get("launches") or [])
                     if l.get("exercise") not in selected]
    launches = sorted(keep_launches + new_launches, key=_launch_key)
    order = {l.get("exercise"): i for i, l in enumerate(launches)}
    keep_rows = [r for r in (base.get("results") or []) if r.get("exercise") not in selected]
    results = sorted(keep_rows + new_results, key=lambda r: order.get(r.get("exercise"), -1))
    sets = list(base_meta.get("sets") or [])
    for s in new_sets:
        if s not in sets:
            sets.append(s)
    meta = {
        "task": "P2.21 prompt lab v2",
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "plan_file": "tools/promptlab/plan.json",
        "url": base_meta.get("url") or run_meta.get("url"),
        "model": base_meta.get("model") or run_meta.get("model"),
        "model_ftype": base_meta.get("model_ftype") or run_meta.get("model_ftype"),
        "build_info": base_meta.get("build_info") or run_meta.get("build_info"),
        "host": base_meta.get("host") or host_info(),
        "doses": {str(l["stage"]): l["dose"] for l in launches
                  if l.get("family") == "scheduled" and l.get("stage") is not None},
        "sweep_doses": [l["dose"] for l in launches if l.get("family") == "sweep"],
        "fallback_doses": {str(l["stage"]): l["dose"] for l in launches
                           if l.get("family") == "fallback" and l.get("stage") is not None},
        "dose_maps": {l["exercise"]: l["dose"] for l in launches
                      if l.get("family") == "path_matrix"},
        "dose_note": ("steering dose is a llama-server launch flag "
                      "(--control-vector-scaled, docs/06 §4); recorded per row"),
        "sampling": run_meta.get("sampling") or lab.SAMPLING,
        "scheduled_doses": lab.SCHEDULED_DOSES,
        "order": run_meta.get("order", base_meta.get("order", "docs")),
        "schema_property_order": (run_meta.get("schema_property_order")
                                  or base_meta.get("schema_property_order")),
        "player_name": run_meta.get("player_name", lab.PLAYER_NAME),
        "sets": sets,
        "runs_per_case": base_meta.get("runs_per_case") or runs_per_case,
        "launches": launches,
    }
    merged = {"meta": meta, "results": results}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(merged, indent=1, ensure_ascii=False), encoding="utf-8")
    log_path = out_path.with_name(out_path.stem + "_launches.log")
    log_path.write_text(sanitize(_log_text(out_path.stem, launches), extras), encoding="utf-8")
    return out_path, log_path, len(results)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--plan", default="all",
                   choices=["scheduled", "offered", "sweep", "fallback",
                            "path_matrix", "all"])
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
    if any(_total_dose(ex["dose"]) for ex in todo
           if not isinstance(ex["dose"], dict)):
        if not a.vector or not Path(a.vector).exists():
            missing.append("LEILA_CVEC (--vector)")
    # P3.04 map doses resolve through vectors.json; a positive key that maps to
    # no file and is not declared unbound refuses the launch, the same rule the
    # game's StageSteering applies.
    for ex in todo:
        if isinstance(ex["dose"], dict):
            vectors, _unbound, unmapped = lab.vector_files(ex["dose"])
            if unmapped:
                raise SystemExit(
                    f"plan.py: dose {ex['dose']} has unmapped positive keys "
                    f"{unmapped} — vectors.json must map or declare them")
            for v in vectors:
                if not Path(v["file"]).exists():
                    missing.append(f"vector file {v['file']} ({v['key']})")
    if missing:
        raise SystemExit("plan.py: local artifacts missing: " + ", ".join(missing) +
                         "\n  see tools/promptlab/README.md §Local artifacts")

    extras = [(a.model, "<model>"), (a.llama_bin, "<llama>"), (a.vector, "<cvec>"),
              (lab.ROOT, "<repo>")]
    base = None
    if out_path.is_file():
        base = json.loads(out_path.read_text(encoding="utf-8"))
        print(f"merging into {_rel(out_path)}: "
              f"{len(base.get('results') or [])} existing turn(s) kept, "
              f"replacing {', '.join(ex['id'] for ex in todo)}")
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
            launch.setdefault(
                "log",
                f"[{ex['id']}] reused {chunk_path.name} (n={len(doc['results'])})\n"
                "no server launch by this run: the chunk and its launch record come from the "
                "run that produced them")
            chunk = {"doc": doc, "launch": launch}
            chunks.append((ex, chunk))
            print(f"{ex['id']}: reused chunk")
            continue
        if _discard_stale_chunk(chunk_path, launch_path):
            print(f"{ex['id']}: discarded the previous chunk "
                  f"(pass --reuse-chunks to merge it instead)")

        sets = [str(lab.SETS_DIR / s) for s in ex["sets"]]
        cmd = ["bash", str(SERVE_SH), "--port", str(port), "--ctx", str(ctx),
               "--ngl", str(ngl)]
        bound_vectors, skipped_unbound = [], []
        if isinstance(ex["dose"], dict):
            # P3.04 dose map: one --vector/--scale pair per bound file; a
            # declared-unbound key (path_mix) is recorded, not launched.
            bound_vectors, skipped_unbound, _u = lab.vector_files(ex["dose"])
            for v in bound_vectors:
                cmd += ["--vector", str(v["file"]), "--scale", "%g" % v["scale"]]
        elif ex["dose"] > 0:
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
                       "--dose", json.dumps(ex["dose"]) if isinstance(ex["dose"], dict)
                       else "%g" % ex["dose"],
                       "--exercise", ex["id"], "--plan", a.plan,
                       "--out", str(chunk_path)]
            if ex.get("only"):
                run_cmd += ["--only", *ex["only"]]
            r = subprocess.run(run_cmd, cwd=str(lab.ROOT), capture_output=True, text=True)
            tail = "\n".join(r.stdout.strip().splitlines()[-8:])
            block = (f"[{ex['id']}] family={ex['family']} stage={ex['stage']} "
                     f"dose={lab.dose_key(ex['dose'])} ready={ready_s}s rc={r.returncode}\n{tail}")
            if r.returncode != 0:
                block += "\n" + sanitize(r.stderr[-2000:], extras)
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
            "vector": (Path(str(a.vector)).name
                       if (a.vector and not isinstance(ex["dose"], dict)
                           and ex["dose"] > 0) else None),
            "vectors": ([f"{Path(v['file']).name}:{v['scale']:g}"
                         for v in bound_vectors] or None),
            "skipped_unbound": skipped_unbound or None,
            "healthy_s": ready_s, "turns": len(doc["results"]),
            "seconds": round(time.time() - t0, 1),
            "log": sanitize(block, extras)}}
        chunk["launch"]["server_args"] = sanitize(" ".join(cmd[2:]), extras)
        launch_path.write_text(json.dumps(chunk["launch"], indent=1), encoding="utf-8")
        chunks.append((ex, chunk))
        print(f"{ex['id']}: {len(doc['results'])} turns at dose {lab.dose_key(ex['dose'])}")

    merged_path, log_path, n = merge(chunks, out_path, runs or 2, extras, base)
    print(f"merged {n} turns -> {_rel(merged_path)}")
    print(f"launch log -> {_rel(log_path)}  ({round(time.time() - started, 1)}s total)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
