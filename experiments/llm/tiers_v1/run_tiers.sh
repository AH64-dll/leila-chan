#!/usr/bin/env bash
# P410a tier driver. Runs the named rows one at a time, in the order given.
# Usage: run_tiers.sh LABEL [LABEL ...]
# Each row: uptime and VRAM before and after, timeout 400, JSONL in $OUT/LABEL.jsonl,
# Godot log in $OUT/LABEL.log. A failed row is recorded (exit code, error lines) and the
# next row still runs. proxy_4gb is valid only while the 8097 llama-server proxy is up.
set -u

REPO="/run/media/amrhares/New Volume/lila/.claude/worktrees/P4"
OUT="/home/amrhares/.cache/leila-native/tiers"
export LEILA_MODEL="/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
mkdir -p "$OUT"

row_flags() {
	case "$1" in
		gpu_cuda) echo "--device=CUDA0" ;;
		gpu_auto) echo "" ;;
		opt_late_events) echo "--device=CUDA0 --late-events=1" ;;
		opt_inner_40) echo "--device=CUDA0 --inner-cap=40" ;;
		opt_both) echo "--device=CUDA0 --late-events=1 --inner-cap=40" ;;
		gpu_fast) echo "--device=CUDA0 --fast=1" ;;
		gpu_vulkan) echo "--device=Vulkan1" ;;
		igpu_vulkan) echo "--device=Vulkan0" ;;
		cpu_4t_fast) echo "--device=cpu --threads=4 --fast=1" ;;
		cpu_6t_fast) echo "--device=cpu --threads=6 --fast=1" ;;
		cpu_8t_fast) echo "--device=cpu --threads=8 --fast=1" ;;
		cpu_12t_fast) echo "--device=cpu --threads=12 --fast=1" ;;
		cpu_default_fast) echo "--device=cpu --fast=1" ;;
		cpu_default_normal) echo "--device=cpu" ;;
		proxy_4gb) echo "" ;;
		*) return 1 ;;
	esac
}

vram() {
	nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || echo "unavailable"
}

run_row() {
	local label="$1" flags rc start lines
	if ! flags="$(row_flags "$label")"; then
		echo "=== $label: unknown label, skipped"
		echo
		return 0
	fi
	rm -f "$OUT/$label.jsonl" "$OUT/$label.log"
	echo "=== $label | ${flags:-auto, no device flag} | --ubatch=128 --cache=1 --dose=4.5 --temp=game"
	echo "uptime before: $(uptime)"
	echo "vram before: $(vram)"
	start=$SECONDS
	(cd "$REPO" && timeout 400 ./tools/godot.sh --headless --path game \
		--script "$REPO/native/tests/cache_scene.gd" -- \
		--out="$OUT/$label.jsonl" --ubatch=128 --cache=1 --dose=4.5 --temp=game $flags) \
		> "$OUT/$label.log" 2>&1
	rc=$?
	echo "uptime after: $(uptime)"
	echo "vram after: $(vram)"
	lines=$(cat "$OUT/$label.jsonl" 2>/dev/null | wc -l)
	echo "exit=$rc seconds=$((SECONDS - start)) jsonl_lines=$lines"
	grep -E "cache_scene|LeilaLLM|SCRIPT ERROR|Parse Error|ERROR" "$OUT/$label.log" | head -60
	echo
}

if [ "$#" -eq 0 ]; then
	echo "usage: $0 LABEL [LABEL ...]" >&2
	exit 2
fi
for label in "$@"; do
	run_row "$label"
done
