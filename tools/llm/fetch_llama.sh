#!/usr/bin/env bash
# Fetch the pinned llama.cpp build (b12024) into tools/llama/llama-b12024.
# Linux: ubuntu tarballs. Windows Git Bash: delegates to the .zip assets too
# (same layout serve.sh expects). CUDA needs the cudart pair; Vulkan is the
# documented fallback if the CUDA build mismatches the driver (P0 risk).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="b12024"; VARIANT="cuda-13.4"; DEST=""
usage() { echo "usage: $0 [--variant cuda-13.4|cuda-12.4|cuda-12.8|vulkan|cpu] [--build bNNNN] [--dest DIR]" >&2; }
while [ $# -gt 0 ]; do case "$1" in
    --variant) VARIANT="$2"; shift 2;;
    --build)   BUILD="$2";   shift 2;;
    --dest)    DEST="$2";    shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
esac; done
DEST="${DEST:-$ROOT/tools/llama/llama-$BUILD}"
BASE="https://github.com/ggml-org/llama.cpp/releases/download/$BUILD"

if [ "${OS:-}" = "Windows_NT" ]; then
    case "$VARIANT" in
        cuda-13.4) FILES="llama-$BUILD-bin-win-cuda-13.4-x64.zip cudart-llama-bin-win-cuda-13.4-x64.zip";;
        cuda-12.4) FILES="llama-$BUILD-bin-win-cuda-12.4-x64.zip cudart-llama-bin-win-cuda-12.4-x64.zip";;
        vulkan)    FILES="llama-$BUILD-bin-win-vulkan-x64.zip";;
        cpu)       FILES="llama-$BUILD-bin-win-cpu-x64.zip";;
        *) echo "no such Windows variant: $VARIANT" >&2; exit 2;;
    esac
    EXT=zip
else
    case "$VARIANT" in
        cuda-13.4) FILES="llama-$BUILD-bin-ubuntu-cuda-13.4-x64.tar.gz cudart-llama-$BUILD-bin-ubuntu-cuda-13.4-x64.tar.gz";;
        cuda-12.8) FILES="llama-$BUILD-bin-ubuntu-cuda-12.8-x64.tar.gz cudart-llama-$BUILD-bin-ubuntu-cuda-12.8-x64.tar.gz";;
        vulkan)    FILES="llama-$BUILD-bin-ubuntu-vulkan-x64.tar.gz";;
        cpu)       FILES="llama-$BUILD-bin-ubuntu-x64.tar.gz";;
        *) echo "no such Linux variant: $VARIANT" >&2; exit 2;;
    esac
    EXT=tar.gz
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for f in $FILES; do
    echo "download  $BASE/$f"
    curl -fL --retry 3 -o "$TMP/$f" "$BASE/$f"
    echo "extract   $f -> $DEST"
    if [ "$EXT" = zip ]; then unzip -oq "$TMP/$f" -d "$DEST"; else tar -xzf "$TMP/$f" -C "$DEST"; fi
done

EXE="$DEST/llama-server"; [ "${OS:-}" = "Windows_NT" ] && EXE="$EXE.exe"
PATH="$DEST:$PATH" "$EXE" --version
echo "Done. Binaries in $DEST (gitignored). Start with: tools/llm/serve.sh"
