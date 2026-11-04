#!/usr/bin/env bash
# P2.22B — regenerate the 14-day campaign simulation curve (CSV).
#
# Usage: tools/meters/campaign.sh [output-dir]
# Default output dir: production/handoffs/media/P2.22B
#
# The CSV comes from the real game code (game/tools/campaign_sim.gd drives
# GameState/Meters/TriggerEngine through three scripted players); this wrapper
# only locates the project and the Godot binary. Deterministic: same checkout ->
# same bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/production/handoffs/media/P2.22B}"
mkdir -p "$OUT"

"$ROOT/tools/godot.sh" --headless --path "$ROOT/game" \
	--script res://tools/campaign_sim.gd -- "--out=$OUT/campaign_curve.csv"
