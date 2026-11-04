"""P3.03 — build the six path control vectors from the residual means.

Input: the per-pair residual means produced by llama-dump-residuals --pairs
(`<trait>.pos.npy` and `<trait>.neg.npy`, shape (200, n_layers, n_embd), each row
the mean over that reply's tokens). Output: one llama.cpp control vector per
trait (`direction.<layer>`, unit L2 per layer) plus a manifest that records the
layer range, the scale convention and the provenance.

Method (docs/06 §2): mean activation difference over the assistant reply tokens,
layers 10-20, normalised per layer. The first principal component of the 200
per-pair differences is computed as a cross-check: `pc1_cos` near 1 means the
mean difference is the dominant direction, not an average of noise.

Usage:
    python3 tools/steering/build_path_vectors.py --means-dir DIR \
        [--out-dir game/data/steering] [--manifest game/data/steering/paths.json] \
        [--record experiments/steering/<date>_path_vectors.json] \
        [--model MODEL.gguf] [--layers 10-20] [--scale 4.0]
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
# positive side semantics; lucid's positive side is the ANCHOR side (docs/06 §2)
POSITIVE_SIDE = {
    "possessive": "possessive/jealous/controlling (YANDERE); negative = secure devotion",
    "unstable": "mood swings, idealise/devalue (SPLIT); negative = steady warmth",
    "contempt": "cold, superior, dismissive (TSUN-BREAK); negative = sincere warmth",
    "hollow": "flat, third-person, forgetting (HOLLOW); negative = engaged first person",
    "aware": "model-aware meta talk (AWAKE); negative = in-character",
    "lucid": "clear-eyed honesty, boundaries, resisting the pull (ANCHOR); negative = "
    "paranoid drift. POSITIVE IS THE ANCHOR SIDE: apply at a NEGATIVE scale at runtime.",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_means(means_dir: Path, trait: str, side: str) -> np.ndarray:
    path = means_dir / f"{trait}.{side}.npy"
    array = np.load(path)
    if array.ndim != 3:
        raise SystemExit(f"{path}: expected (n_pairs, n_layers, n_embd), got {array.shape}")
    if array.shape[0] != 200:
        raise SystemExit(f"{path}: {array.shape[0]} pairs, want 200")
    if not np.isfinite(array).all():
        raise SystemExit(f"{path}: non-finite values")
    return array.astype(np.float32, copy=False)


def write_cvec(path: Path, directions: np.ndarray, layer_lo: int, n_layer: int,
               meta: dict[str, str]) -> None:
    from gguf import GGUFWriter

    writer = GGUFWriter(str(path), "controlvector")
    writer.add_string("controlvector.model_hint", "qwen35")
    writer.add_uint32("controlvector.layer_count", int(n_layer))
    for key, value in meta.items():
        writer.add_string(key, value)
    for index, direction in enumerate(directions):
        # direction.N is block index N (0-indexed), matching steer_build.py and
        # common_control_vector_load; the first row is --layers' low bound.
        writer.add_tensor(f"direction.{layer_lo + index}", direction.astype(np.float32))
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()


def main() -> int:
    root = Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--means-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=root / "game" / "data" / "steering")
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--record", type=Path, default=None)
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--layers", default="10-20")
    parser.add_argument("--n-layer", type=int, default=32,
                        help="model block count written to controlvector.layer_count")
    parser.add_argument(
        "--scale",
        type=float,
        default=4.0,
        help="runtime scale the blind read schedules (docs/06 §3 path_mix mid-range)",
    )
    parser.add_argument("--extract-record", type=Path, default=None,
                        help="extract.json written by extract_pairs.py (provenance)")
    parser.add_argument("--pairs-dir", type=Path,
                        default=root / "tools" / "steering" / "pairs")
    args = parser.parse_args()

    layer_lo, layer_hi = (int(part) for part in args.layers.split("-"))
    if layer_hi < layer_lo:
        raise SystemExit(f"bad --layers {args.layers}")
    n_layers = layer_hi - layer_lo + 1

    manifest_path = args.manifest or (args.out_dir / "paths.json")
    record_path = args.record or (
        root / "experiments" / "steering" / f"{dt.date.today()}_path_vectors.json"
    )
    args.out_dir.mkdir(parents=True, exist_ok=True)

    model_meta = {}
    if args.model is not None:
        model_meta = {"model": args.model.name, "model_sha256": sha256(args.model)}

    extract_meta = {}
    extract_record = None
    if args.extract_record is not None:
        raw = json.loads(args.extract_record.read_text(encoding="utf-8"))
        extract_record = str(args.extract_record)
        extract_meta = {
            "record": extract_record,
            "model_sha256": raw.get("model_sha256"),
            "binary_sha256": raw.get("binary_sha256"),
            "threads": raw.get("threads"),
            "ngl": raw.get("ngl"),
            "runs": {
                trait: {"seconds": run.get("seconds"), "summary": run.get("summary")}
                for trait, run in raw.get("runs", {}).items()
            },
        }
    pairs_manifest = json.loads((args.pairs_dir / "manifest.json").read_text(encoding="utf-8"))

    vectors: dict[str, dict] = {}
    records: dict[str, dict] = {}
    for trait in TRAITS:
        pos = load_means(args.means_dir, trait, "pos")
        neg = load_means(args.means_dir, trait, "neg")
        if pos.shape != neg.shape:
            raise SystemExit(f"{trait}: side shapes differ {pos.shape} vs {neg.shape}")
        if pos.shape[1] != n_layers:
            raise SystemExit(f"{trait}: {pos.shape[1]} layers on disk, want {n_layers}")
        _, disk_layers, n_embd = pos.shape

        pairs = (pos - neg).reshape(pos.shape[0], disk_layers * n_embd)
        diff = pairs.mean(axis=0).reshape(disk_layers, n_embd)
        # first principal component of the per-pair differences, per layer
        pc1_cos = np.empty(disk_layers, dtype=np.float32)
        sign_agreement = np.empty(disk_layers, dtype=np.float32)
        for layer in range(disk_layers):
            block = pairs[:, layer * n_embd:(layer + 1) * n_embd]
            block = block - block.mean(axis=0, keepdims=True)
            # right singular vector = principal direction in activation space
            _, _, vh = np.linalg.svd(block, full_matrices=False)
            pc = vh[0].astype(np.float32)
            denom = float(np.linalg.norm(diff[layer]) * np.linalg.norm(pc))
            # a degenerate block (identical differences) has no PC to compare
            cos = float(diff[layer] @ pc) / denom if denom > 1e-12 else 0.0
            pc1_cos[layer] = abs(cos)
            raw_block = pairs[:, layer * n_embd:(layer + 1) * n_embd]
            sign_agreement[layer] = float(np.mean(raw_block @ diff[layer] >= 0.0))

        raw_norm = np.linalg.norm(diff, axis=1)
        directions = diff / (raw_norm[:, None] + 1e-12)
        if not np.isfinite(directions).all():
            raise SystemExit(f"{trait}: non-finite directions")
        if np.any(raw_norm < 1e-6):
            raise SystemExit(f"{trait}: a layer has a near-zero mean difference")

        out_file = args.out_dir / f"{trait}.gguf"
        write_cvec(
            out_file,
            directions,
            layer_lo=layer_lo,
            n_layer=args.n_layer,
            meta={
                "leila.task": "P3.03",
                "leila.trait": trait,
                "leila.layers": f"{layer_lo}-{layer_hi}",
                "leila.method": "mean activation difference over assistant reply tokens, unit L2 per layer",
                "leila.source": "tools/steering/pairs/" + f"{trait}.jsonl",
            },
        )

        mean_residual_norm = float(np.linalg.norm((pos + neg) / 2.0, axis=2).mean())
        vectors[trait] = {
            "file": f"res://data/steering/{trait}.gguf",
            "sha256": sha256(out_file),
            "layers": f"{layer_lo}-{layer_hi}",
            "n_embd": int(n_embd),
            "pairs": int(pos.shape[0]),
            "pair_source": f"tools/steering/pairs/{trait}.jsonl",
            "pair_source_sha256": sha256(args.pairs_dir / f"{trait}.jsonl"),
            "positive_side": POSITIVE_SIDE[trait],
            "mean_diff_norm": [round(float(value), 3) for value in raw_norm],
            "pc1_cos": [round(float(value), 3) for value in pc1_cos],
            "pc1_cos_mean": round(float(pc1_cos.mean()), 3),
            "pair_sign_agreement_mean": round(float(sign_agreement.mean()), 3),
            "mean_reply_residual_norm": round(mean_residual_norm, 3),
        }
        records[trait] = {
            "gguf": out_file.name,
            "raw_norm": vectors[trait]["mean_diff_norm"],
            "pc1_cos": vectors[trait]["pc1_cos"],
            "sign_agreement": [round(float(value), 3) for value in sign_agreement],
            "mean_reply_residual_norm": vectors[trait]["mean_reply_residual_norm"],
        }
        print(
            f"{trait:10s} layers {layer_lo}-{layer_hi}  n_embd {n_embd}  "
            f"||diff|| L{layer_lo}={raw_norm[0]:.3f} L{layer_hi}={raw_norm[-1]:.3f}  "
            f"pc1_cos mean {pc1_cos.mean():.3f}  sign {sign_agreement.mean():.3f}  "
            f"-> {out_file.name} ({vectors[trait]['sha256'][:12]})"
        )

    manifest = {
        "version": 1,
        "task": "P3.03",
        "doc": "docs/06_STEERING.md §2 (vector library) and §3 (dose schedule)",
        "built_by": "tools/steering/build_path_vectors.py",
        "built_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "model": model_meta.get("model", "Qwen3.5-4B-Q4_K_M.gguf"),
        "model_sha256": model_meta.get("model_sha256"),
        "layers": f"{layer_lo}-{layer_hi}",
        "method": (
            "For each of the 200 pairs, render context as the user turn and each side as the "
            "assistant turn, mean the residual over the assistant reply tokens at every layer, "
            "subtract negative from positive per pair, average the 200 differences, then "
            "normalise each layer to unit L2. No system prompt."
        ),
        "scale_convention": (
            "Each direction.<layer> is unit L2, so the llama.cpp scale is the dose: a scale of "
            "1.0 adds exactly 1.0 to that layer's residual, matching the malice vector's "
            "convention (unit neurons, runtime scale = dose × R). The scale the blind read "
            "schedules is `blind_read_scale`; docs/06 §3's path_mix (1.0-5.0) is that scale band."
        ),
        "blind_read_scale": args.scale,
        "anchors": {
            "lucid": (
                "positive is the ANCHOR side; ANCHOR applies the vector at a NEGATIVE scale "
                "(docs/06 §2). The blind read still tests it at +scale to prove the direction "
                "is identifiable."
            )
        },
        "extraction": extract_meta,
        "vectors": vectors,
        "blind_read": None,
        "decision": None,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    record = {
        "task": "P3.03",
        "doc": "docs/06_STEERING.md §2",
        "built_at": manifest["built_at"],
        "model": manifest["model"],
        "model_sha256": manifest["model_sha256"],
        "layers": manifest["layers"],
        "scale": args.scale,
        "means_dir": str(args.means_dir),
        "extraction": extract_meta,
        "vectors": records,
        "manifest": str(manifest_path),
    }
    record_path.parent.mkdir(parents=True, exist_ok=True)
    record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {manifest_path} and {record_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
