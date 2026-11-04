#!/usr/bin/env bash
# P2.13: measure the assembled fixed system prompt for every stage × shipped path
# with the real Qwen tokenizer. Layers follow docs/08 §1: persona, player line,
# stage, path, rules + glosses. Budget: docs/07 §3.1 system ≤ 900 tokens.
#
# Needs the local artifacts (main-tree only; see tools/local_artifacts.md):
#   LEILA_LLAMA_BIN=<llama.cpp b12024 release dir>   (default: tools/llama/llama-b12024)
#   LEILA_MODEL=<Qwen3.5-4B-Q4_K_M.gguf>             (default: models/Qwen3.5-4B-Q4_K_M.gguf)
#   PLAYER_NAME=<name>                               (default: Ren; max length 16)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOK="${LEILA_LLAMA_BIN:-$ROOT/tools/llama/llama-b12024}/llama-tokenize"
MODEL="${LEILA_MODEL:-$ROOT/models/Qwen3.5-4B-Q4_K_M.gguf}"
PLAYER="${PLAYER_NAME:-Ren}"
PROMPTS="$ROOT/game/data/prompts"

[ -x "$TOK" ] || { echo "llama-tokenize not found at $TOK (set LEILA_LLAMA_BIN)" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "model not found at $MODEL (set LEILA_MODEL)" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
count_tokens() {
	"$TOK" --model "$MODEL" --file "$1" 2>/dev/null | grep -cE '^[[:space:]]*[0-9]+ -> '
}

printf '%-6s %-8s %6s\n' stage path tokens
for stage in 0 1 2 3 4 5; do
	if [ "$stage" -lt 2 ]; then paths=("-"); else paths=(YANDERE AWAKE); fi
	for path in "${paths[@]}"; do
		{
			cat "$PROMPTS/persona.md"
			printf 'The player is a boy called %s.\n' "$PLAYER"
			cat "$PROMPTS/stage_$stage.md"
			if [ "$path" != "-" ]; then cat "$PROMPTS/path_$path.md"; fi
			cat "$PROMPTS/rules.md" "$PROMPTS/glosses.md"
		} | sed "s/{player_name}/$PLAYER/g" > "$TMP"
		printf '%-6s %-8s %6s\n' "$stage" "$path" "$(count_tokens "$TMP")"
	done
done
