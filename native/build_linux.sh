#!/usr/bin/env bash
# Build libleila_llm for Linux x86_64 and stage its shared libs into the addon.
# Usage: bash native/build_linux.sh [--clean]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CACHE="$HOME/.cache/leila-native"
export LEILA_NATIVE_DEPS="${LEILA_NATIVE_DEPS:-$CACHE/deps}"
BUILD="$CACHE/build-linux"
API="$CACHE/api/extension_api.json"
OUT="$REPO/game/addons/leila_llm/bin/linux"
JOBS=8

log() { echo "build_linux: $*"; }

if [ "${1:-}" = "--clean" ]; then
	log "removing $BUILD"
	rm -rf "$BUILD"
fi

mkdir -p "$CACHE"
log "fetching pinned deps into $LEILA_NATIVE_DEPS"
bash "$HERE/fetch_deps.sh"

if [ ! -f "$API" ]; then
	log "dumping Godot extension API to $API"
	mkdir -p "$(dirname "$API")"
	SCRATCH="$(mktemp -d)"
	trap 'rm -rf "$SCRATCH"' EXIT
	(cd "$SCRATCH" && "$REPO/tools/godot.sh" --headless --dump-extension-api >"$CACHE/api-dump.log" 2>&1)
	mv "$SCRATCH/extension_api.json" "$API"
fi

log "configuring (Ninja, Release) in $BUILD"
cmake -S "$HERE" -B "$BUILD" -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DLEILA_NATIVE_DEPS="$LEILA_NATIVE_DEPS" \
	-DGODOTCPP_CUSTOM_API_FILE="$API"

log "building with -j $JOBS"
cmake --build "$BUILD" -j "$JOBS"

log "staging shared libs into $OUT"
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 \( -name 'libleila_llm.so*' -o -name 'libllama*.so*' -o -name 'libggml*.so*' \) -delete
# cp -P keeps the SONAME symlinks (libllama.so.0 -> libllama.so.0.0.N) intact.
find "$BUILD" \( -type f -o -type l \) -regextype posix-extended \
	-regex '.*/lib(leila_llm|llama|ggml)[^/]*\.so([.][0-9][0-9.]*)?' \
	-exec cp -P {} "$OUT/" \;

test -f "$OUT/libleila_llm.so" || { log "libleila_llm.so was not staged"; exit 1; }
missing="$(ldd "$OUT/libleila_llm.so" | grep -c 'not found' || true)"
if [ "$missing" != "0" ]; then
	log "ldd reports $missing unresolved libraries"
	exit 1
fi
log "staged $(ls -1 "$OUT" | wc -l) files into $OUT"
ls -1 "$OUT"
bash "$HERE/stage_gpu_backends.sh"
log "done"
