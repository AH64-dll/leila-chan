#!/usr/bin/env bash
# Start llama-server (pinned llama.cpp b12024) for Leila-chan prototype work.
# --jinja (Qwen chat template), full GPU offload (-ngl 99), one request slot
# (-np 1) — the same shape the M0 experiments used (experiments/steer_sweep.py).
# An optional control vector is applied at launch; changing the dose means
# restarting the server (docs/06 §4).
#
# Paths default to the repo layout; override with LEILA_MODEL / LEILA_LLAMA_BIN
# env vars or --model / --bin. Works on Linux and Windows Git Bash.
# Mirrors tools/llm/serve.ps1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL="${LEILA_MODEL:-$ROOT/models/Qwen3.5-4B-Q4_K_M.gguf}"
BIN="${LEILA_LLAMA_BIN:-$ROOT/tools/llama/llama-b12024}"
PORT=8089; CTX=8192; NGL=99; VECTOR=""; VSCALE=1

usage() {
    cat >&2 <<EOF
usage: $0 [--model GGUF] [--bin DIR] [--port N] [--ctx N] [--ngl N] \\
          [--vector CVEC_GGUF] [--scale S]
  --vector/--scale  append --control-vector-scaled CVEC:S (dose; e.g. 4)
EOF
}
while [ $# -gt 0 ]; do case "$1" in
    --model)  MODEL="$2";  shift 2;;
    --bin)    BIN="$2";    shift 2;;
    --port)   PORT="$2";   shift 2;;
    --ctx)    CTX="$2";    shift 2;;
    --ngl)    NGL="$2";    shift 2;;
    --vector) VECTOR="$2"; shift 2;;
    --scale)  VSCALE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
esac; done

case "${OS:-}" in
    Windows_NT) EXE="$BIN/llama-server.exe"; export PATH="$BIN:$PATH";;
    *) EXE="$BIN/llama-server"; export LD_LIBRARY_PATH="$BIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}";;
esac
[ -f "$EXE" ]   || { echo "llama-server not found at $EXE — run tools/llm/fetch_llama.sh (see tools/llm/README.md)" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "model not found at $MODEL — see tools/llm/README.md" >&2; exit 1; }

ARGS=(-m "$MODEL" -ngl "$NGL" -c "$CTX" --jinja --port "$PORT" -np 1)
if [ -n "$VECTOR" ]; then
    [ -f "$VECTOR" ] || { echo "control vector not found: $VECTOR" >&2; exit 1; }
    ARGS+=(--control-vector-scaled "$VECTOR:$VSCALE")
fi

VER="$("$EXE" --version 2>&1 | head -n1 || true)"
echo "llama-server ${VER:-(version unknown)}"
echo "  bin:    $EXE"
echo "  model:  $MODEL"
echo "  args:   ${ARGS[*]}"
echo "  health: http://127.0.0.1:$PORT/health"
exec "$EXE" "${ARGS[@]}"
