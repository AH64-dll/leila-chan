#!/usr/bin/env bash
# Stage the optional GPU backends (CUDA, Vulkan) next to libleila_llm.so.
# Every source is optional: a missing one is reported and skipped, so a
# CPU-only checkout still stages cleanly. build_linux.sh calls this last,
# because its staging step deletes libggml* before copying.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$REPO/game/addons/leila_llm/bin/linux"
CUDA_SRC="$REPO/tools/llama/gpu-cuda/llama-b12024"
CUDART_SRC="$REPO/tools/llama/gpu-cuda/cudart-llama-b12024-bin-ubuntu-cuda-13.4-x64"
VULKAN_SRC="$REPO/tools/llama/gpu-vulkan/llama-b12024"

log() { echo "stage_gpu_backends: $*"; }

STAGED=0
mkdir -p "$OUT"
shopt -s nullglob

stage() {
	local src="$1"
	if [ -e "$src" ]; then
		cp -P "$src" "$OUT/"
		STAGED=$((STAGED + 1))
		log "staged $(basename "$src")"
	else
		log "skipped $(basename "$src") (not found at $src)"
	fi
}

stage "$CUDA_SRC/libggml-cuda.so"
for lib in "$CUDART_SRC"/*; do
	stage "$lib"
done
stage "$VULKAN_SRC/libggml-vulkan.so"

log "staged $STAGED GPU files into $OUT"
ls -1 "$OUT" | grep -E '^(libggml-(cuda|vulkan)|libcu)' || true
