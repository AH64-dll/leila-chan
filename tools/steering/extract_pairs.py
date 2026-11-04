"""P3.03 — run the residual dump over all six pair sets.

Calls `tools/steering/prepare_pairs.py` once, concatenates the two sides of each
trait into one TSV (positive rows first, then negative), runs
`llama-dump-residuals --pairs` once per trait, then splits the (400, L, d) means
back into `<trait>.pos.npy` / `<trait>.neg.npy`. One model load per trait instead
of two, and no per-prompt .npy is ever written (the pair means are all the build
needs: ~45 MB per side, not ~11 GB of token dumps).

A run that cannot measure every prompt aborts and writes no means: the two sides
of a pair must stay row-aligned, or the difference is meaningless.

Usage:
    python3 tools/steering/extract_pairs.py --model MODEL.gguf \
        --binary tools/steering/build/llama-dump-residuals \
        [--means-dir DIR] [--threads N] [--layers 10-20] [-ngl N]

Writes <means-dir>/<trait>.{pos,neg}.npy, <means-dir>/extract.json and prints the
model/binary hashes plus the reply-token stats for the experiment record.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent.parent
TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
PAIRS = 200


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument(
        "--binary", type=Path, default=ROOT / "tools" / "steering" / "build" / "llama-dump-residuals"
    )
    parser.add_argument(
        "--means-dir", type=Path, default=ROOT / "experiments" / "steering" / "pairs_means"
    )
    parser.add_argument("--tsv-dir", type=Path, default=ROOT / "experiments" / "steering" / "pairs_tsv")
    parser.add_argument("--threads", type=int, default=10)
    parser.add_argument("--skip-existing", action="store_true",
                        help="reuse a trait whose pos/neg means already exist (restart support)")
    parser.add_argument("--layers", default="10-20")
    parser.add_argument("-ngl", "--n-gpu-layers", type=int, default=0)
    args = parser.parse_args()

    for path in (args.model, args.binary):
        if not path.exists():
            raise SystemExit(f"missing {path}")
    args.means_dir.mkdir(parents=True, exist_ok=True)

    started = dt.datetime.now(dt.timezone.utc)
    prepared = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "steering" / "prepare_pairs.py"),
         "--out-dir", str(args.tsv_dir)],
        check=True, capture_output=True, text=True,
    )
    print(prepared.stdout.strip())

    record = {
        "task": "P3.03",
        "started": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "model": args.model.name,
        "model_sha256": sha256(args.model),
        "binary": str(args.binary),
        "binary_sha256": sha256(args.binary),
        "layers": args.layers,
        "threads": args.threads,
        "ngl": args.n_gpu_layers,
        "runs": {},
    }

    for trait in TRAITS:
        done_pos = args.means_dir / f"{trait}.pos.npy"
        done_neg = args.means_dir / f"{trait}.neg.npy"
        if args.skip_existing and done_pos.exists() and done_neg.exists():
            shape = list(np.load(done_pos, mmap_mode="r").shape)
            print(f"=== {trait}: existing means kept {shape}")
            record["runs"][trait] = {"reused": True, "shape": shape[1:]}
            continue
        pos_tsv = args.tsv_dir / f"{trait}.pos.tsv"
        neg_tsv = args.tsv_dir / f"{trait}.neg.tsv"
        pos_lines = pos_tsv.read_text(encoding="utf-8").splitlines()
        neg_lines = neg_tsv.read_text(encoding="utf-8").splitlines()
        if len(pos_lines) != PAIRS or len(neg_lines) != PAIRS:
            raise SystemExit(f"{trait}: {len(pos_lines)}/{len(neg_lines)} lines, want {PAIRS}")
        both_tsv = args.tsv_dir / f"{trait}.both.tsv"
        both_tsv.write_text("\n".join(pos_lines + neg_lines) + "\n", encoding="utf-8")
        both_npy = args.means_dir / f"{trait}.both.npy"
        command = [
            str(args.binary), "-m", str(args.model), "--pairs", str(both_tsv),
            "--means-out", str(both_npy), "--layers", args.layers,
            "--threads", str(args.threads), "-ngl", str(args.n_gpu_layers),
        ]
        print(f"=== {trait}: {' '.join(command)}")
        begin = time.time()
        run = subprocess.run(command, capture_output=True, text=True)
        elapsed = time.time() - begin
        sys.stderr.write(run.stderr)
        if run.returncode != 0:
            raise SystemExit(f"{trait}: dump exited {run.returncode}; no means written")
        means = np.load(both_npy)
        if means.shape != (2 * PAIRS, *means.shape[1:]):
            raise SystemExit(f"{trait}: bad means shape {means.shape}")
        np.save(args.means_dir / f"{trait}.pos.npy", means[:PAIRS])
        np.save(args.means_dir / f"{trait}.neg.npy", means[PAIRS:])
        both_npy.unlink()  # the split files are the artefact; keep the disk lean

        summary = next(
            (line for line in reversed(run.stderr.splitlines()) if "pair means" in line), ""
        )
        record["runs"][trait] = {
            "seconds": round(elapsed, 1),
            "summary": summary.strip(),
            "shape": list(means.shape[1:]),
            # keep workstation paths out of the committed record
            "command": ["<model>" if item == str(args.model) else item for item in command],
        }
        print(f"=== {trait}: {elapsed:.1f}s  {summary.strip()}")

    record["finished"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record_path = args.means_dir / "extract.json"
    record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(TRAITS)} x 2 means and {record_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
