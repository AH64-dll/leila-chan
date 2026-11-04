#!/usr/bin/env python3
"""P3.05 evidence: every path's signature moves appear in prompt-lab transcripts.

docs/01 §4.1–§4.6 defines each fracture path by a handful of signature moves.
`game/data/prompts/signature_moves.json` lists, per path, the regexes the
generated dialogue must show. This script reads committed prompt-lab result
files (tools/promptlab/results/*.json), groups the generated turns by path, and
fails if any move never appears for its path.

It checks the committed transcript (a deterministic artifact). Re-running the
lab produces a new file; point this script at it to check that run instead —
which is a fresh sample, so a move may legitimately miss on a 4B model.

    python3 production/handoffs/media/P3.05_signature_moves.py \
        tools/promptlab/results/2026-11-04_v2_p305_paths.json

The default file is the P3.05 run it was authored against.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SIGNATURES = ROOT / "game" / "data" / "prompts" / "signature_moves.json"
DEFAULT_RESULTS = [
    ROOT / "tools" / "promptlab" / "results" / "2026-11-04_v3_p305_paths.json",
]


def load_rows(paths):
    rows = []
    for path in paths:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
        for row in doc.get("results", []):
            rows.append({"source": Path(path).name, "row": row})
    return rows


def spoken_lines(row):
    """Every line the model produced that the player can see or she can think."""
    lines = []
    out = row.get("out")
    if not isinstance(out, dict):
        return lines
    inner = str(out.get("inner", "")).strip()
    if inner:
        lines.append(inner)
    for beat in out.get("beats", []) or []:
        if isinstance(beat, dict):
            say = str(beat.get("say", "")).strip()
            if say:
                lines.append(say)
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("results", nargs="*", default=None,
                        help="prompt-lab results JSON files (default: the P3.05 run)")
    parser.add_argument("--quiet", action="store_true", help="only print failures")
    args = parser.parse_args()
    files = [Path(p) for p in args.results] if args.results else DEFAULT_RESULTS
    missing = [str(p) for p in files if not p.exists()]
    if missing:
        print("missing results file(s): " + ", ".join(missing), file=sys.stderr)
        return 2

    table = json.loads(SIGNATURES.read_text(encoding="utf-8"))["paths"]
    rows = load_rows(files)
    print("rows: %d from %s" % (len(rows), ", ".join(p.name for p in files)))
    failures = 0
    for path in table:
        path_rows = [r for r in rows if str(r["row"].get("path", "")) == path]
        if not path_rows:
            print("FAIL %s: no prompt-lab rows" % path)
            failures += 1
            continue
        lines = [(r["source"], r["row"].get("id", "?"), line)
                 for r in path_rows for line in spoken_lines(r["row"])]
        if not args.quiet:
            print("\n%s (%s): %d turns, %d lines"
                  % (path, table[path]["doc"], len(path_rows), len(lines)))
        for pattern in table[path]["transcript"]:
            rx = re.compile(pattern)
            hits = [(src, cid, line) for src, cid, line in lines if rx.search(line)]
            if hits:
                if not args.quiet:
                    src, cid, line = hits[0]
                    print("  ok   %-52s x%-3d  [%s %s] %s"
                          % (pattern, len(hits), src, cid, line[:90]))
            else:
                print("  FAIL %-52s no line in %d turns" % (pattern, len(path_rows)))
                failures += 1
    print("\n%s: %d unresolved signature move(s)"
          % ("FAIL" if failures else "PASS", failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
