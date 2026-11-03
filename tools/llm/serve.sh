#!/usr/bin/env bash
# Start llama-server (pinned llama.cpp b12024) for Leila-chan prototype work.
# --jinja (Qwen chat template), full GPU offload (-ngl 99), one request slot
# (-np 1) — the same shape the M0 experiments used (experiments/steer_sweep.py).
# An optional control vector is applied at launch; changing the dose means
# restarting the server (docs/06 §4).
#
# --vector paths: llama.cpp parses --control-vector-scaled as FNAME:SCALE and
# splits on ':' and ',', so a FNAME containing ':' can never reach it — on
# Windows that means `X:/...` absolute paths and the ambiguous `X:file` form.
# Both launchers therefore normalize through tools/llm/cvec_path.py: a
# drive-rooted path becomes a relative path against the server cwd (same drive
# required), and `X:file` or any name containing ':'/',' is rejected with an
# explanation. Accepted: relative paths, POSIX absolute paths, UNC paths,
# `X:/...` on the cwd's drive. Needs python3/py on PATH when --vector is used.
#
# Paths default to the repo layout; override with LEILA_MODEL / LEILA_LLAMA_BIN
# env vars or --model / --bin. Works on Linux and Windows Git Bash.
# Mirrors tools/llm/serve.ps1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL="${LEILA_MODEL:-$ROOT/models/Qwen3.5-4B-Q4_K_M.gguf}"
BIN="${LEILA_LLAMA_BIN:-$ROOT/tools/llama/llama-b12024}"
PORT=8089; CTX=8192; NGL=99; VECTOR=""; VSCALE=1; DRY=0

usage() {
    cat >&2 <<EOF
usage: $0 [--model GGUF] [--bin DIR] [--port N] [--ctx N] [--ngl N] \\
          [--vector CVEC_GGUF] [--scale S] [--dry-run]
  --vector/--scale  append --control-vector-scaled CVEC:S (dose; e.g. 4).
      CVEC may be relative, POSIX-absolute, UNC or (Git Bash) X:/... on the
      cwd's drive — drive paths are normalized to same-drive relative ones
      (see header). X:file and names containing ':'/',' are rejected.
  --dry-run         print the resolved command line and exit without serving
EOF
}
while [ $# -gt 0 ]; do case "$1" in
    --model)   MODEL="$2";  shift 2;;
    --bin)     BIN="$2";    shift 2;;
    --port)    PORT="$2";   shift 2;;
    --ctx)     CTX="$2";    shift 2;;
    --ngl)     NGL="$2";    shift 2;;
    --vector)  VECTOR="$2"; shift 2;;
    --scale)   VSCALE="$2"; shift 2;;
    --dry-run) DRY=1;       shift;;
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
    # Normalize CVEC for the FNAME:SCALE parser via tools/llm/cvec_path.py
    # (see header): drive paths become same-drive relative paths. On Git Bash
    # the helper (and python itself) sees Windows paths, so translate first.
    CVEC_PY="$(dirname "${BASH_SOURCE[0]}")/cvec_path.py"
    PYBIN=""
    for c in python3 python "py -3"; do command -v ${c%% *} >/dev/null 2>&1 && { PYBIN=$c; break; }; done
    [ -n "$PYBIN" ] || { echo "--vector needs python3 (or py -3) on PATH for cvec_path.py normalization" >&2; exit 1; }
    VP="$VECTOR"; PCWD=""
    if [ "${OS:-}" = "Windows_NT" ] && command -v cygpath >/dev/null 2>&1; then
        VP="$(cygpath -wa "$VECTOR")"; PCWD="$(cygpath -w "$PWD")"
    fi
    FLAG="$($PYBIN "$CVEC_PY" --scale "$VSCALE" ${PCWD:+--cwd "$PCWD"} -- "$VP")" \
        || { echo "control vector rejected: $VECTOR" >&2; exit 1; }
    CVEC_ARG="$(printf '%s\n' "$FLAG" | tail -n1)"
    ARGS+=(--control-vector-scaled "$CVEC_ARG")
fi

VER="$("$EXE" --version 2>&1 | head -n1 || true)"
echo "llama-server ${VER:-(version unknown)}"
echo "  bin:    $EXE"
echo "  model:  $MODEL"
echo "  args:   ${ARGS[*]}"
echo "  health: http://127.0.0.1:$PORT/health"
[ "$DRY" = 1 ] && { echo "  (dry-run: not starting)"; exit 0; }
exec "$EXE" "${ARGS[@]}"
