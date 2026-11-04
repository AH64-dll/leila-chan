#!/usr/bin/env bash
# P2.01 — regenerate the 100-turn meters simulation curve (CSV) and its plot.
#
# Usage: tools/meters/sim.sh [output-dir]
# Default output dir: production/handoffs/media/P2.01
#
# The CSV comes from the real game code (game/tools/meters_sim.gd drives
# GameState/Meters); the SVG/PNG come from tools/meters/plot.py (stdlib only).
# Deterministic: same checkout -> same bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/production/handoffs/media/P2.01}"
mkdir -p "$OUT"

CSV="$OUT/meters_curve.csv"
SVG="$OUT/meters_curve.svg"

"$ROOT/tools/godot.sh" --headless --path "$ROOT/game" \
	--script res://tools/meters_sim.gd -- "--out=$CSV"
python3 "$ROOT/tools/meters/plot.py" "$CSV" "$SVG"
