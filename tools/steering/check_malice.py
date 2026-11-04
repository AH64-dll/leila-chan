"""Sanity-check residual dumps against the known malice direction (P3.01).

Usage:
    python3 tools/steering/check_malice.py <dump-dir> [<steered-dir>] \
        [--cvec experiments/steering/evil_qwen_unit.gguf] [--scale 8]

Layout contract shared with llama-dump-residuals:
    <dir>/prompt_NNN.npy : float32, shape (n_layers, n_tokens, n_embd),
    layer index offset = --lo (default 10). The tensor captured is the model's
    per-layer residual output ("l_out-<il>"), taken AFTER the control vector
    is applied at that layer.

Checks (per dump dir):
  1. Every captured layer is finite (no NaN/Inf) and non-degenerate
     (std > 0, norms comparable across layers — a dead capture is zeros).
  2. Projection of the residual onto each malice direction (unit vectors from
     the control-vector gguf, direction.13/14) is finite for every prompt.
  3. If a steered dir (same prompts, --cvec F:SCALE) is given: for each
     direction layer, mean(steered projection) - mean(base projection) ≈ SCALE
     (tol 30% — the injection adds SCALE * unit(dir) to every token).

Deps: numpy, gguf==0.19.0 (requirements-experiments.txt).
"""
import argparse
import glob
import os
import sys

import numpy as np
import gguf


def load_dirs(path):
    """control-vector gguf -> {layer: unit direction (n_embd,)}."""
    r = gguf.GGUFReader(path)
    out = {}
    for t in r.tensors:
        if not t.name.startswith("direction."):
            continue
        v = t.data.astype(np.float32)
        n = np.linalg.norm(v)
        if n > 0:
            out[int(t.name.split(".")[1])] = v / n
    return out


def load_dumps(d, lo):
    """-> {prompt_idx: arr (n_layers, n_tokens, n_embd)} ; layer il = row il-lo."""
    out = {}
    for f in sorted(glob.glob(os.path.join(d, "prompt_*.npy"))):
        arr = np.load(f)
        if arr.ndim != 3 or not np.issubdtype(arr.dtype, np.floating):
            sys.exit(f"{f}: expected (n_layers, n_tokens, n_embd) float array, got {arr.shape} {arr.dtype}")
        idx = int(os.path.basename(f)[7:10])
        out[idx] = (idx, arr.astype(np.float32))
    if not out:
        sys.exit(f"no prompt_*.npy in {d}")
    return out


def check_finite(dumps, lo, dirs, label):
    fails = 0
    norms = []
    for idx, arr in dumps.values():
        for li in range(arr.shape[0]):
            a = arr[li]
            il = lo + li
            if not np.isfinite(a).all():
                print(f"  FAIL {label} prompt {idx} layer {il}: NaN/Inf")
                fails += 1
            if a.std() == 0:
                print(f"  FAIL {label} prompt {idx} layer {il}: degenerate (std=0)")
                fails += 1
        norms.append(np.linalg.norm(arr, axis=2).mean())
    m = float(np.mean(norms))
    print(f"  {label}: {len(dumps)} prompts, mean ||residual|| per layer ≈ {m:.1f}")
    if m == 0:
        print(f"  FAIL {label}: all-zero capture")
        fails += 1
    # projection onto each known direction, last-token and all-token means
    for il, u in sorted(dirs.items()):
        if not (lo <= il < lo + next(iter(dumps.values()))[1].shape[0]):
            continue
        projs = [arr[il - lo] @ u for _, arr in dumps.values()]
        p = np.concatenate(projs)
        if not np.isfinite(p).all():
            print(f"  FAIL {label}: non-finite projection on direction.{il}")
            fails += 1
        else:
            print(f"  {label}: proj(direction.{il}) mean {p.mean():+.3f} std {p.std():.3f} "
                  f"(last-token {np.mean([a[-1] for a in projs]):+.3f})")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base_dir")
    ap.add_argument("steered_dir", nargs="?")
    ap.add_argument("--cvec", default=os.path.join(os.path.dirname(__file__), "..", "..",
                                                 "experiments", "steering", "evil_qwen_unit.gguf"))
    ap.add_argument("--scale", type=float, default=8.0)
    ap.add_argument("--lo", type=int, default=10, help="first dumped layer index")
    a = ap.parse_args()

    dirs = load_dirs(a.cvec)
    if not dirs:
        sys.exit(f"no direction.* tensors in {a.cvec}")
    print(f"malice directions: layers {sorted(dirs)} (unit vectors, n_embd={len(next(iter(dirs.values())))})")

    base = load_dumps(a.base_dir, a.lo)
    fails = check_finite(base, a.lo, dirs, "base")

    if a.steered_dir:
        ste = load_dumps(a.steered_dir, a.lo)
        fails += check_finite(ste, a.lo, dirs, "steered")
        if set(ste) != set(base):
            sys.exit(f"prompt sets differ: {sorted(base)} vs {sorted(ste)}")
        for il, u in sorted(dirs.items()):
            if not (a.lo <= il < a.lo + next(iter(base.values()))[1].shape[0]):
                continue
            li = il - a.lo
            shift = [float((ste[i][1][li] @ u).mean() - (base[i][1][li] @ u).mean())
                     for i in sorted(base)]
            mean_shift = float(np.mean(shift))
            verdict = "OK" if abs(mean_shift - a.scale) <= 0.3 * a.scale else "FAIL"
            if verdict == "FAIL":
                fails += 1
            print(f"  direction.{il}: expected shift ≈ {a.scale:+.2f}, "
                  f"got {mean_shift:+.3f} (per-prompt {min(shift):+.2f}..{max(shift):+.2f}) [{verdict}]")

    print("PASS" if fails == 0 else f"{fails} FAILURES")
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    main()
