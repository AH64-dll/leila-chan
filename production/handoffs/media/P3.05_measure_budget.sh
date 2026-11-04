#!/usr/bin/env bash
# P3.05: measure the assembled system prompt with the real Qwen tokenizer.
#
# Layers follow docs/08 §1: persona, player line, stage, path (+ the runner-up's
# one-line hybrid share), rules + glosses. That is the **authored** block (D18
# cap 900). The second table adds the per-turn "Offered this turn —" tail
# (cap 200) and measures the **whole system message** (cap 1100), so a real turn
# is read against the cap it can actually break.
#
# Needs the local artifacts (main-tree only; see tools/local_artifacts.md):
#   LEILA_LLAMA_BIN=<llama.cpp b12024 release dir>   (default: tools/llama/llama-b12024)
#   LEILA_MODEL=<Qwen3.5-4B-Q4_K_M.gguf>             (default: models/Qwen3.5-4B-Q4_K_M.gguf)
#   PLAYER_NAME=<name>                               (default: Ren; New Game max 16 chars)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOK="${LEILA_LLAMA_BIN:-$ROOT/tools/llama/llama-b12024}/llama-tokenize"
MODEL="${LEILA_MODEL:-$ROOT/models/Qwen3.5-4B-Q4_K_M.gguf}"
PLAYER="${PLAYER_NAME:-Ren}"
PROMPTS="$ROOT/game/data/prompts"
STAGE_GATES="$ROOT/game/data/stage_gates.json"
PATHS=(YANDERE SPLIT TSUN HOLLOW AWAKE ANCHOR)
AUTHORED_CAP=900
TAIL_CAP=200
TOTAL_CAP=1100

[ -x "$TOK" ] || { echo "llama-tokenize not found at $TOK (set LEILA_LLAMA_BIN)" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "model not found at $MODEL (set LEILA_MODEL)" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
count_tokens() {
	"$TOK" --model "$MODEL" --file "$1" 2>/dev/null | grep -cE '^[[:space:]]*[0-9]+ -> '
}
# PromptBuilder._offered_line (D18): music, fx, cue, action from stage_gates.json,
# joined with "; " after "Offered this turn — " and closed with ".". No trailing
# newline: the builder appends the tail after the rules layer with one "\n".
offered_line() {
	python3 - "$STAGE_GATES" "$1" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
row = data["stages"][sys.argv[2]]
parts = []
for key, source in (("music", "music"), ("fx", "fx"), ("cue", "cues"), ("action", "actions")):
    values = row.get(source, [])
    if values:
        parts.append("%s: %s" % (key, ", ".join(values)))
sys.stdout.write("Offered this turn — " + "; ".join(parts) + ".")
PY
}
# docs/08 §1 order; the runner-up's contribution is its first non-empty line,
# exactly what PromptBuilder._first_content_line hands over. The optional 4th
# argument is the per-turn offered tail.
assemble() {
	local stage="$1" path="$2" runner="$3" offered="${4:-}"
	{
		cat "$PROMPTS/persona.md"
		printf 'The player is a boy called %s.\n' "$PLAYER"
		cat "$PROMPTS/stage_$stage.md"
		if [ -n "$path" ]; then
			cat "$PROMPTS/path_$path.md"
			# PromptBuilder appends the runner-up's first line to the primary
			# module's text with a single "\n" (the files already end in a newline).
			if [ -n "$runner" ] && [ "$runner" != "$path" ]; then
				grep -v '^[[:space:]]*$' "$PROMPTS/path_$runner.md" | head -n1
			fi
		fi
		cat "$PROMPTS/rules.md" "$PROMPTS/glosses.md"
		if [ -n "$offered" ]; then
			printf '%s\n' "$offered"
		fi
	} | sed "s/{player_name}/$PLAYER/g" > "$TMP"
	count_tokens "$TMP"
}

echo "player name: $PLAYER   model: $(basename "$MODEL")   authored cap: $AUTHORED_CAP"
printf '%-6s %-8s %-8s %6s\n' stage path runner tokens
declare -A WORST_PAIR=()
for stage in 0 1 2 3 4 5; do
	if [ "$stage" -lt 2 ]; then
		t=$(assemble "$stage" "" ""); printf '%-6s %-8s %-8s %6s\n' "$stage" - - "$t"
	else
		for path in "${PATHS[@]}"; do
			t=$(assemble "$stage" "$path" ""); printf '%-6s %-8s %-8s %6s\n' "$stage" "$path" - "$t"
		done
		# worst ordered pair for this stage (the hybrid's share included)
		best=0; best_pair=""
		for path in "${PATHS[@]}"; do
			for runner in "${PATHS[@]}"; do
				[ "$runner" = "$path" ] && continue
				t=$(assemble "$stage" "$path" "$runner")
				if [ "$t" -gt "$best" ]; then best=$t; best_pair="$path+$runner"; fi
			done
		done
		WORST_PAIR[$stage]="$best_pair"
		printf '%-6s %-17s %6s  (worst pair at stage %s)\n' "$stage" "$best_pair" "$best" "$stage"
	fi
done
echo "worst authored assembly above is the gate; every row must be <= $AUTHORED_CAP"

echo
echo "=== whole system message (authored + the real per-turn offered tail; D18 caps: tail <= $TAIL_CAP, total <= $TOTAL_CAP)"
for name in Ren Maximiliana-Rose; do
	PLAYER="$name"
	echo "-- player name: $name"
	printf '%-6s %-17s %9s %6s %6s\n' stage pair authored tail total
	worst_total=0
	for stage in 0 1 2 3 4 5; do
		if [ "$stage" -lt 2 ]; then
			label="-"; path=""; runner=""
		else
			label="${WORST_PAIR[$stage]}"
			path="${label%%+*}"
			runner="${label##*+}"
		fi
		authored=$(assemble "$stage" "$path" "$runner")
		total=$(assemble "$stage" "$path" "$runner" "$(offered_line "$stage")")
		tail=$((total - authored))
		if [ "$total" -gt "$worst_total" ]; then worst_total=$total; fi
		printf '%-6s %-17s %9s %6s %6s\n' "$stage" "$label" "$authored" "$tail" "$total"
	done
	echo "worst whole message for $name: $worst_total (cap $TOTAL_CAP)"
done
