#!/usr/bin/env bash
# P3.05: measure the assembled fixed system prompt for every stage × shipped path
# (and every ordered runner-up pair) with the real Qwen tokenizer.
#
# Layers follow docs/08 §1: persona, player line, stage, path (+ the runner-up's
# one-line 25% hybrid share), rules + glosses. Budget: docs/07 §3.1 system ≤ 900.
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
PATHS=(YANDERE SPLIT TSUN HOLLOW AWAKE ANCHOR)

[ -x "$TOK" ] || { echo "llama-tokenize not found at $TOK (set LEILA_LLAMA_BIN)" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "model not found at $MODEL (set LEILA_MODEL)" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
count_tokens() {
	"$TOK" --model "$MODEL" --file "$1" 2>/dev/null | grep -cE '^[[:space:]]*[0-9]+ -> '
}
# docs/08 §1 order; the runner-up's contribution is its first non-empty line,
# exactly what PromptBuilder._first_content_line hands over.
assemble() {
	local stage="$1" path="$2" runner="$3"
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
	} | sed "s/{player_name}/$PLAYER/g" > "$TMP"
	count_tokens "$TMP"
}

echo "player name: $PLAYER   model: $(basename "$MODEL")   budget: 900"
printf '%-6s %-8s %-8s %6s\n' stage path runner tokens
WORST=0
for stage in 0 1 2 3 4 5; do
	if [ "$stage" -lt 2 ]; then
		t=$(assemble "$stage" "" ""); printf '%-6s %-8s %-8s %6s\n' "$stage" - - "$t"
	else
		for path in "${PATHS[@]}"; do
			t=$(assemble "$stage" "$path" ""); printf '%-6s %-8s %-8s %6s\n' "$stage" "$path" - "$t"
		done
		# worst ordered pair for this stage (the hybrid's 25% share included)
		best=0; best_pair=""
		for path in "${PATHS[@]}"; do
			for runner in "${PATHS[@]}"; do
				[ "$runner" = "$path" ] && continue
				t=$(assemble "$stage" "$path" "$runner")
				if [ "$t" -gt "$best" ]; then best=$t; best_pair="$path+$runner"; fi
			done
		done
		printf '%-6s %-17s %6s  (worst pair at stage %s)\n' "$stage" "$best_pair" "$best" "$stage"
	fi
done
echo "worst single assembly above is the gate; every row must be <= 900"
