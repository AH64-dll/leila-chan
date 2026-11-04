"""P3.03 — turn the six contrastive pair sets into the TSV the dump tool reads.

Each line becomes `context<TAB>reply`, rendered by llama-dump-residuals as a
two-turn chat (user = context, assistant = reply). Tabs and newlines cannot
appear in the pair fields (the pair-set tests reject control characters), so the
TSV is lossless; the script asserts the round-trip anyway.

Usage:
    python3 tools/steering/prepare_pairs.py [--pairs-dir DIR] [--out-dir DIR]

Writes <out-dir>/<trait>.pos.tsv and <out-dir>/<trait>.neg.tsv, 200 lines each,
and prints the sha256 of every source and output file for the experiment record.
The output directory is a regenerable local artifact (experiments/steering/...).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
PAIRS_PER_SET = 200


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_rows(path: Path) -> list[dict]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    if len(rows) != PAIRS_PER_SET:
        raise SystemExit(f"{path}: {len(rows)} records, want {PAIRS_PER_SET}")
    return rows


def main() -> int:
    root = Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pairs-dir", type=Path, default=root / "tools" / "steering" / "pairs")
    parser.add_argument(
        "--out-dir", type=Path, default=root / "experiments" / "steering" / "pairs_tsv"
    )
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.pairs_dir / "manifest.json").read_text(encoding="utf-8"))
    recorded = manifest["duplication"]["effective_unique_per_file"]
    summary: dict[str, dict] = {}

    for trait in TRAITS:
        source = args.pairs_dir / f"{trait}.jsonl"
        rows = load_rows(source)
        if len({row["id"] for row in rows}) != PAIRS_PER_SET:
            raise SystemExit(f"{source}: duplicate ids")
        if len({(row["positive"], row["negative"]) for row in rows}) != recorded[trait]:
            raise SystemExit(f"{source}: effective-unique count drifted from the manifest")

        entry = {"source": source.name, "source_sha256": sha256(source)}
        for side in ("pos", "neg"):
            field = "positive" if side == "pos" else "negative"
            out = args.out_dir / f"{trait}.{side}.tsv"
            lines = []
            for row in rows:
                context, reply = row["context"], row[field]
                for value in (context, reply):
                    if "\t" in value or "\n" in value or "\r" in value:
                        raise SystemExit(f"{row['id']}: control character in {field!r}")
                lines.append(f"{context}\t{reply}")
            out.write_text("\n".join(lines) + "\n", encoding="utf-8")

            # round-trip: the dump tool must see exactly the pair fields
            back = [line.split("\t", 1) for line in out.read_text(encoding="utf-8").splitlines()]
            if len(back) != PAIRS_PER_SET or any(len(pair) != 2 for pair in back):
                raise SystemExit(f"{out}: malformed TSV")
            for row, (context, reply) in zip(rows, back):
                if context != row["context"] or reply != row[field]:
                    raise SystemExit(f"{out}: round-trip mismatch at {row['id']}")
            entry[f"{side}_tsv"] = out.name
            entry[f"{side}_sha256"] = sha256(out)
            entry[f"{side}_lines"] = len(lines)
        summary[trait] = entry

    record = args.out_dir / "manifest.json"
    record.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    for trait, entry in summary.items():
        print(
            f"{trait:10s} {entry['pos_lines']} pos + {entry['neg_lines']} neg  "
            f"src {entry['source_sha256'][:12]}  "
            f"pos {entry['pos_sha256'][:12]}  neg {entry['neg_sha256'][:12]}"
        )
    print(f"wrote {len(summary)} x 2 TSV files to {args.out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
