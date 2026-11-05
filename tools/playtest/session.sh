#!/usr/bin/env bash
# Run one human playtest session and capture its evidence.
#
#   tools/playtest/session.sh [--session ID] [--name NAME] [--build PATH|dev]
#                             [--no-tail] [--allow-no-server] [--force] [--check]
#
# What it does:
#   1. creates production/playtests/P2/human/<session-id>/ and seeds survey.md,
#      obs_sheet.md and session_log.md from the templates in that folder;
#   2. exports LEILA_PLAYTEST_SESSION / LEILA_PLAYTEST_BUNDLE and points the game's
#      user:// at <bundle>/_userdata/ (gitignored) so the transcript is isolated;
#   3. launches the game — a debug export if one is present, else the dev run;
#   4. tails the live transcript into <bundle>/telemetry.jsonl while the game runs;
#   5. finalises <bundle>/session.meta.json with the exit code and end time.
#
# `--check` resolves the build, checks the backend and prints the bundle path without
# creating or launching anything. Exit codes: 0 ok, 1 launch/runtime error, 2 preflight failed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE="${LEILA_PLAYTEST_PHASE:-P2}"
SESSIONS_DIR_OVERRIDE=""
INTENDED_PATH=""
GAME_DIR="$ROOT/game"
SERVER_URL="${LEILA_PLAYTEST_SERVER_URL:-http://127.0.0.1:8089}"

SESSION="S$(date +%Y%m%d-%H%M%S)"
PLAYER_NAME=""
BUILD_ARG=""
DO_TAIL=1
CHECK_SERVER=1
FORCE=0
CHECK_ONLY=0
usage() {
    cat >&2 <<'EOF'
usage: tools/playtest/session.sh [options]

  --session ID       bundle name (default: S<date>-<time>)
  --name NAME        the character name you expect them to type (recorded only;
                     the game still asks for it)
  --build PATH|dev   force a binary, or "dev" for tools/godot.sh --path game
  --no-tail          do not live-tail the transcript (collect.sh still merges raw/)
  --allow-no-server  launch even when /health does not answer
  --force            reuse an existing non-empty bundle directory
  --phase P2|P3      playtest phase (default: P2, or LEILA_PLAYTEST_PHASE)
  --sessions-dir DIR explicitly specify where bundles are stored
  --style PATH       intended path or style (e.g. YANDERE, Card 1)
  --check            preflight only: resolve the build, check the server, print paths
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --session) SESSION="${2:?--session needs a value}"; shift 2 ;;
        --name) PLAYER_NAME="${2:?--name needs a value}"; shift 2 ;;
        --build) BUILD_ARG="${2:?--build needs a value}"; shift 2 ;;
        --no-tail) DO_TAIL=0; shift ;;
        --allow-no-server) CHECK_SERVER=0; shift ;;
        --force) FORCE=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage ;;
        --phase) PHASE="${2:?--phase needs a value}"; shift 2 ;;
        --sessions-dir) SESSIONS_DIR_OVERRIDE="${2:?--sessions-dir needs a value}"; shift 2 ;;
        --style|--intended-path) INTENDED_PATH="${2:?--style needs a value}"; shift 2 ;;
        *) echo "session.sh: unknown argument $1" >&2; usage ;;
    esac
done

SESSION="${SESSION//[^A-Za-z0-9._-]/_}"
if [ -n "$SESSIONS_DIR_OVERRIDE" ]; then
    HUMAN_DIR="$SESSIONS_DIR_OVERRIDE"
elif [ "$PHASE" = "P3" ] || [ "$PHASE" = "3" ]; then
    HUMAN_DIR="$ROOT/production/playtests/P3/human"
else
    HUMAN_DIR="$ROOT/production/playtests/P2/human"
fi
BUNDLE="$HUMAN_DIR/$SESSION"
META="$BUNDLE/session.meta.json"

# Resolve the build. An explicit LEILA_PLAYTEST_BUILD or --build wins; then the
# conventional export locations; otherwise the dev run.
resolve_build() {
    if [ -n "$BUILD_ARG" ]; then
        if [ "$BUILD_ARG" = "dev" ]; then printf 'dev'; return; fi
        if [ ! -x "$BUILD_ARG" ]; then
            echo "session.sh: --build $BUILD_ARG is not executable" >&2
            exit 2
        fi
        printf '%s' "$BUILD_ARG"; return
    fi
    if [ -n "${LEILA_PLAYTEST_BUILD:-}" ]; then
        if [ ! -x "$LEILA_PLAYTEST_BUILD" ]; then
            echo "session.sh: LEILA_PLAYTEST_BUILD=$LEILA_PLAYTEST_BUILD is not executable" >&2
            exit 2
        fi
        printf '%s' "$LEILA_PLAYTEST_BUILD"; return
    fi
    local candidate
    for candidate in \
        "$ROOT/build/Leila-chan.x86_64" \
        "$ROOT/build/leila-chan.x86_64" \
        "$ROOT/game/build/Leila-chan.x86_64" \
        "$ROOT/dist/Leila-chan.x86_64" \
        "$ROOT/export/Leila-chan.x86_64"; do
        if [ -x "$candidate" ]; then printf '%s' "$candidate"; return; fi
    done
    printf 'dev'
}

server_ok() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 2 "$SERVER_URL/health" >/dev/null 2>&1
        return
    fi
    python3 - "$SERVER_URL" <<'PY'
import sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1].rstrip("/") + "/health", timeout=2) as response:
        response.read(1)
except Exception:
    sys.exit(1)
PY
}

BUILD="$(resolve_build)"
if [ "$BUILD" = "dev" ]; then
    BUILD_DESC="dev godot $(tr -d '[:space:]' < "$ROOT/game/.godot-version")"
    BUILD_KIND="dev"
    EXPORT_PATH=""
else
    BUILD_DESC="export $(basename "$BUILD")"
    BUILD_KIND="export"
    EXPORT_PATH="$BUILD"
fi

SERVER_STATE="skipped"
if [ "$CHECK_SERVER" -eq 1 ] && [ -z "${LEILA_OWN_SERVER:-}" ]; then
    if server_ok; then
        SERVER_STATE="ok $SERVER_URL"
    else
        SERVER_STATE="DOWN $SERVER_URL"
    fi
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "session.sh: preflight"
    echo "  build:    $BUILD_DESC ($BUILD_KIND)"
    echo "  server:   $SERVER_STATE"
    echo "  game dir: $GAME_DIR"
    echo "  bundle:   $BUNDLE"
    echo "  telemetry: $BUNDLE/telemetry.jsonl"
    if [ "$SERVER_STATE" = "DOWN $SERVER_URL" ]; then
        echo "  -> start the backend first: tools/llm/serve.sh   (curl -s $SERVER_URL/health)" >&2
        exit 2
    fi
    exit 0
fi

if [ -d "$BUNDLE" ] && [ "$FORCE" -eq 0 ] && [ -n "$(ls -A "$BUNDLE" 2>/dev/null || true)" ]; then
    echo "session.sh: $BUNDLE already exists and is not empty (use --force to reuse it)" >&2
    exit 2
fi

if [ "$SERVER_STATE" = "DOWN $SERVER_URL" ]; then
    echo "session.sh: no healthy backend at $SERVER_URL." >&2
    echo "  start it with: tools/llm/serve.sh" >&2
    echo "  (or pass --allow-no-server if the app launches its own server with LEILA_OWN_SERVER=1)" >&2
    exit 2
fi

mkdir -p "$BUNDLE/raw"
for template in survey.md obs_sheet.md; do
    [ -e "$BUNDLE/$template" ] || cp "$HUMAN_DIR/$template" "$BUNDLE/$template"
done
[ -e "$BUNDLE/session_log.md" ] || cp "$HUMAN_DIR/session_log_template.md" "$BUNDLE/session_log.md"
: >"$BUNDLE/telemetry.jsonl"

SESSION="$SESSION" BUILD_DESC="$BUILD_DESC" BUILD_KIND="$BUILD_KIND" \
    EXPORT_PATH="$EXPORT_PATH" SERVER_URL="$SERVER_URL" PLAYER_NAME="$PLAYER_NAME" \
    INTENDED_PATH="$INTENDED_PATH" PHASE="$PHASE" \
    python3 - "$META" <<'PY'
import json
import os
import platform
import sys
from datetime import datetime

meta = {
    "v": 1,
    "session_id": os.environ["SESSION"],
    "started_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    "ended_at": "",
    "status": "running",
    "build": os.environ["BUILD_DESC"],
    "build_kind": os.environ["BUILD_KIND"],
    "export_path": os.environ["EXPORT_PATH"],
    "game_exit_code": None,
    "server_url": os.environ["SERVER_URL"],
    "player_name_hint": os.environ["PLAYER_NAME"],
    "host": platform.system(),
    "intended_path": os.environ.get("INTENDED_PATH", ""),
    "phase": os.environ.get("PHASE", "P2"),
    "synthetic": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(meta, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY

export XDG_DATA_HOME="$BUNDLE/_userdata"
export LEILA_PLAYTEST_SESSION="$SESSION"
export LEILA_PLAYTEST_BUNDLE="$BUNDLE"

GAME_PID=""
WATCH_PID=""
FINALIZED=0

finalize_meta() {
    local status="$1" code="$2"
    META_STATUS="$status" META_CODE="$code" python3 - "$META" <<'PY'
import json
import os
import sys
from datetime import datetime

path = sys.argv[1]
meta = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            meta = json.load(handle)
    except (OSError, json.JSONDecodeError):
        meta = {}
raw_code = os.environ.get("META_CODE", "")
meta.update(
    {
        "v": 1,
        "status": os.environ["META_STATUS"],
        "game_exit_code": int(raw_code) if raw_code.lstrip("-").isdigit() else None,
        "ended_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
}

cleanup() {
    local code=$?
    trap - EXIT INT TERM
    if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
        kill "$WATCH_PID" 2>/dev/null || true
        wait "$WATCH_PID" 2>/dev/null || true
    fi
    if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
        kill "$GAME_PID" 2>/dev/null || true
        wait "$GAME_PID" 2>/dev/null || true
    fi
    if [ "$FINALIZED" -eq 0 ]; then
        finalize_meta "aborted" "$code"
        echo "session.sh: session aborted; $BUNDLE/session.meta.json marked 'aborted'" >&2
    fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Live tail: the transcript file only appears once the first turn completes, so poll
# for the debug directory and tail the newest transcript until the game process ends.
watch_telemetry() {
    local last="" tail_pid=""
    while kill -0 "$GAME_PID" 2>/dev/null; do
        local debug_dir=""
        debug_dir="$(find "$BUNDLE/_userdata" -type d -name debug -print -quit 2>/dev/null || true)"
        if [ -n "$debug_dir" ]; then
            local newest=""
            newest="$(ls -1t "$debug_dir"/turns_*.jsonl 2>/dev/null | head -n 1 || true)"
            if [ -n "$newest" ] && [ "$newest" != "$last" ]; then
                if [ -n "$tail_pid" ] && kill -0 "$tail_pid" 2>/dev/null; then
                    kill "$tail_pid" 2>/dev/null || true
                fi
                tail -c +1 -F --pid="$GAME_PID" --sleep-interval=0.2 "$newest" \
                    >>"$BUNDLE/telemetry.jsonl" &
                tail_pid=$!
                last="$newest"
                printf 'session.sh: capturing %s\n' "${newest#"$BUNDLE"/}"
            fi
        fi
        sleep 0.4
    done
    if [ -n "$tail_pid" ]; then
        wait "$tail_pid" 2>/dev/null || true
    fi
}

echo "session.sh: session $SESSION"
echo "session.sh: build $BUILD_DESC"
echo "session.sh: server $SERVER_STATE"
echo "session.sh: bundle $BUNDLE"
echo "session.sh: telemetry starts after the first completed turn"

if [ "$BUILD" = "dev" ]; then
    "$ROOT/tools/godot.sh" --path "$GAME_DIR" &
else
    "$BUILD" &
fi
GAME_PID=$!

if [ "$DO_TAIL" -eq 1 ]; then
    watch_telemetry &
    WATCH_PID=$!
fi

set +e
wait "$GAME_PID"
GAME_EXIT=$?
set -e

if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
fi

# Keep the pristine transcript next to the bundle: collect.sh merges raw/ into
# telemetry.jsonl, so a tail that started late or a rotated file loses nothing.
DEBUG_DIR="$(find "$BUNDLE/_userdata" -type d -name debug -print -quit 2>/dev/null || true)"
if [ -n "$DEBUG_DIR" ]; then
    cp -p "$DEBUG_DIR"/*.jsonl "$BUNDLE/raw/" 2>/dev/null || true
fi

finalize_meta "ended" "$GAME_EXIT"
FINALIZED=1

turns="$(grep -c '"type": *"turn"' "$BUNDLE/telemetry.jsonl" 2>/dev/null || true)"
lines="$(wc -l <"$BUNDLE/telemetry.jsonl" 2>/dev/null || echo 0)"
echo
echo "session.sh: game exited with $GAME_EXIT"
echo "session.sh: telemetry $lines line(s), ${turns:-0} turn(s)"
if [ "${turns:-0}" -eq 0 ]; then
    echo "session.sh: WARNING no turn was captured. Check that the backend was up and that" >&2
    echo "  the build is a DEBUG export (release builds write no transcripts, docs/07 §5)." >&2
fi
echo
echo "Next:"
echo "  1. the participant fills $BUNDLE/survey.md"
echo "  2. you fill $BUNDLE/obs_sheet.md and $BUNDLE/session_log.md"
echo "  3. tools/playtest/collect.sh $SESSION"
echo "  4. after all three sessions: python3 tools/playtest/score.py"
exit 0
